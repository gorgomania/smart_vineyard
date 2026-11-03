import { Controller } from "@hotwired/stimulus"
import { fileChecksum } from "utils/file_checksum"

const MAX_FILE_SIZE = 1073741824 // 1 ГБ
const DIRECT_UPLOAD_URL = "/rails/active_storage/direct_uploads"

// Все файлы (включая ZIP) сразу грузятся на сервер прямой загрузкой ActiveStorage, тем же протоколом, что DirectUpload:
// MD5 файла → POST direct_uploads (blob и адрес загрузки) → PUT файла. Шаги свои, а не DirectUpload, чтобы видеть
// прогресс проверки (MD5 гигабайтного файла считается минуты) и проверять файлы по одному: первый начинает
// грузиться, пока проверяются следующие, а не все ждут, пока досчитаются все.
// При отправке формы уходят только signed id: сами файлы второй раз не передаются
export default class extends Controller {
  static targets = [
    "fileInput", "dropZone", "previewContainer", "errorContainer",
    "progressContainer", "progressBar", "progressPercent", "progressStatus",
    "submitBtn", "form"
  ]

  connect() {
    // ключ name_size → { file, isZip, checked, loaded, status: queued|checking|uploading|done|error, signedId,
    //                    abort, xhr, wrapper, overlay }
    this.uploads = new Map()
    this.checkQueue = Promise.resolve() // проверка (MD5) — по одному файлу: диск читается последовательно
    this.batch = null // { startedAt, baseLoaded, timer } — текущая серия загрузок, для оценки оставшегося времени

    // Уход со страницы при незаконченной загрузке — только с подтверждения: файлы без отправки формы
    // в папку не попадут. beforeunload — закрытие вкладки и перезагрузка, turbo:before-visit — ссылки сайта
    this.warnOnUnload = (event) => { if (this.pending().length > 0) event.preventDefault() }
    this.confirmVisit = (event) => { if (!this.mayLeave()) event.preventDefault() }
    window.addEventListener("beforeunload", this.warnOnUnload)
    document.addEventListener("turbo:before-visit", this.confirmVisit)
    this.render()
  }

  // Ушли со страницы (в том числе кнопкой браузера «назад»: Turbo не перезагружает страницу, и сам браузер
  // ничего не обрывает) — останавливаем проверку и загрузку, иначе гигабайты шли бы на сервер впустую
  disconnect() {
    clearInterval(this.batch?.timer)
    window.removeEventListener("beforeunload", this.warnOnUnload)
    document.removeEventListener("turbo:before-visit", this.confirmVisit)
    this.uploads.forEach(entry => {
      entry.abort.abort()
      entry.xhr?.abort()
    })
    this.uploads.clear()
  }

  // Ссылка «Назад» (history#back — переход по истории, turbo:before-visit его не видит)
  confirmLeave(event) {
    if (this.mayLeave()) return
    event.preventDefault()
    event.stopImmediatePropagation() // следующее действие на ссылке — history#back — не выполняется
  }

  // Согласие запоминаем: «Назад» без истории — обычный переход по ссылке, и turbo:before-visit спросил бы второй раз
  mayLeave() {
    this.leaveConfirmed ||= this.pending().length === 0 ||
      confirm("Файлы ещё загружаются. Уйти со страницы? Загрузка прервётся")
    return this.leaveConfirmed
  }

  fileInputChange(event) {
    event.preventDefault()
    this.errorContainerTarget.innerHTML = ""
    this.addFiles(this.fileInputTarget.files)
    // Чтобы повторный выбор того же файла снова вызвал change
    this.fileInputTarget.value = ""
  }

  // Подсветку рисуют варианты data-dragover: в разметке. Не классы bg-brand-soft и т. п. из JS: у них та же
  // специфичность, что у фона зоны, и победит тот, что раньше в CSS, — после палитры это был фон зоны
  dragOver(event) {
    event.preventDefault()
    event.stopPropagation()
    this.dropZoneTarget.dataset.dragover = ""
  }

  dragLeave() {
    delete this.dropZoneTarget.dataset.dragover
  }

  drop(event) {
    event.preventDefault()
    event.stopPropagation()
    this.errorContainerTarget.innerHTML = ""
    delete this.dropZoneTarget.dataset.dragover
    this.addFiles(event.dataTransfer.files)
  }

  submit(event) {
    const done = [ ...this.uploads.values() ].filter(u => u.status === "done")
    if (this.pending().length > 0 || done.length === 0) {
      event.preventDefault()
      if (done.length === 0) this.showError("Нет загруженных файлов")
      return
    }

    this.appendHidden("signed_blob_ids", done.filter(u => !u.isZip).map(u => u.signedId))
    this.appendHidden("signed_zip_ids", done.filter(u => u.isZip).map(u => u.signedId))
    // Файлы уже на сервере: отключённое поле не попадает в тело запроса
    this.fileInputTarget.disabled = true
  }

  // --- добавление файлов ---

  addFiles(files) {
    Array.from(files).forEach(file => {
      const key = `${file.name}_${file.size}`
      if (this.uploads.has(key)) return

      const isZip = file.name.toLowerCase().endsWith(".zip")
      if (file.size > MAX_FILE_SIZE) return this.showError("Недопустимый размер файла " + file.name)
      if (!(isZip || file.type.startsWith("image/") || file.type.startsWith("video/"))) {
        return this.showError("Недопустимый тип файла " + file.name)
      }

      const entry = {
        key, file, isZip, checked: 0, loaded: 0, status: "queued", signedId: null,
        abort: new AbortController(), xhr: null
      }
      this.uploads.set(key, entry)
      this.buildPreview(entry)
      // Загрузку не ждём: пока файл грузится, очередь уже проверяет следующий
      this.checkQueue = this.checkQueue.then(() => this.prepare(entry))
    })
    this.render()
  }

  // Проверка (MD5) и создание blob, затем загрузка — без ожидания
  async prepare(entry) {
    if (!this.uploads.has(entry.key)) return // убрали, пока ждал очереди

    try {
      entry.status = "checking"
      this.render()
      const checksum = await fileChecksum(entry.file, {
        signal: entry.abort.signal,
        onProgress: (bytes) => { entry.checked = bytes; this.renderEntry(entry) }
      }).catch(error => {
        if (error.name === "AbortError") throw error
        // Текст браузера (файл изменился на диске, WebAssembly запрещён и т. п.) — в консоль, пользователю — суть
        console.error(`Проверка "${entry.file.name}":`, error)
        throw new Error("не удалось прочитать файл. Выберите его ещё раз")
      })
      const blob = await this.createBlob(entry.file, checksum, entry.abort.signal)
      if (!this.uploads.has(entry.key)) return // убрали, пока создавался blob: файл не отправляем
      this.upload(entry, blob)
    } catch (error) {
      if (error.name !== "AbortError") this.fail(entry, error.message)
    }
  }

  async createBlob(file, checksum, signal) {
    let response
    try {
      response = await fetch(DIRECT_UPLOAD_URL, {
        method: "POST",
        signal,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest",
          "X-CSRF-Token": document.querySelector('[name="csrf-token"]')?.content
        },
        body: JSON.stringify({
          blob: { filename: file.name, content_type: file.type || "application/octet-stream", byte_size: file.size, checksum }
        })
      })
    } catch (error) {
      if (error.name === "AbortError") throw error
      throw new Error("нет связи с сервером")
    }
    const data = await response.json().catch(() => ({}))
    // Свой текст сервера (DirectUploadsController: тип или размер), иначе — статус
    if (!response.ok) throw new Error(data.error || `сервер не принял файл (код ${response.status})`)
    return data
  }

  upload(entry, blob) {
    const xhr = new XMLHttpRequest()
    xhr.open("PUT", blob.direct_upload.url, true)
    Object.entries(blob.direct_upload.headers).forEach(([ name, value ]) => xhr.setRequestHeader(name, value))
    xhr.upload.addEventListener("progress", (e) => {
      entry.loaded = e.loaded
      this.render()
    })
    xhr.addEventListener("load", () => {
      if (!this.uploads.has(entry.key)) return
      if (xhr.status >= 200 && xhr.status < 300) {
        entry.status = "done"
        entry.loaded = entry.file.size
        entry.signedId = blob.signed_id
        this.render()
      } else {
        this.fail(entry, `сервер не сохранил файл (код ${xhr.status})`)
      }
    })
    // Обрыв соединения (status 0): сеть, перезапуск сервера, сон компьютера
    xhr.addEventListener("error", () => this.fail(entry, "соединение прервано"))

    entry.xhr = xhr
    entry.status = "uploading"
    this.render()
    xhr.send(entry.file.slice()) // как BlobUpload в ActiveStorage: тело без имени и типа файла, заголовки — от сервера
  }

  fail(entry, reason) {
    if (!this.uploads.has(entry.key)) return // удалён пользователем
    entry.status = "error"
    this.showError(`Ошибка загрузки "${entry.file.name}": ${reason}`)
    this.render()
  }

  remove(entry) {
    this.uploads.delete(entry.key)
    entry.wrapper.remove()

    if (entry.status === "queued" || entry.status === "checking") {
      entry.abort.abort() // проверка и создание blob останавливаются, файл не отправляется
    } else if (entry.status === "uploading") {
      entry.xhr?.abort()
    } else if (entry.status === "done") {
      const csrfToken = document.querySelector('[name="csrf-token"]').content
      fetch(`/active_storage/blobs/${entry.signedId}`, {
        method: "DELETE",
        headers: { "X-CSRF-Token": csrfToken }
      })
    }
    this.render()
  }

  // --- превью ---

  buildPreview(entry) {
    const wrapper = document.createElement("div")
    wrapper.className = "relative"
    entry.wrapper = wrapper

    if (entry.isZip) {
      const tile = document.createElement("div")
      tile.className = "w-full aspect-square bg-brand-tint rounded-lg border-2 border-brand-pale flex flex-col items-center justify-center"
      tile.innerHTML = `
        <span class="text-xs text-ink-soft mt-2">ZIP архив</span>
        <span class="text-xs text-slate-500">${this.formatMb(entry.file.size)} МБ</span>
      `
      wrapper.appendChild(tile)
    } else {
      const img = new Image()
      img.className = "w-full aspect-square object-cover rounded-lg"
      wrapper.appendChild(img)
      if (entry.file.type.startsWith("video/")) {
        this.videoFrame(entry.file, url => { img.src = url })
        // По центру превью любого размера (inset-0 + m-auto); показывается после загрузки — см. renderEntry
        entry.playIcon = new Image()
        entry.playIcon.src = "/circle-play.png"
        entry.playIcon.className = "hidden absolute inset-0 m-auto w-12 h-12 pointer-events-none"
        wrapper.appendChild(entry.playIcon)
      } else {
        img.src = URL.createObjectURL(entry.file)
        img.onload = () => URL.revokeObjectURL(img.src)
      }
    }

    entry.overlay = document.createElement("div")
    entry.overlay.className = "absolute inset-0 bg-black/50 rounded-lg flex items-center justify-center text-white text-xs"
    wrapper.appendChild(entry.overlay)

    const removeBtn = document.createElement("button")
    removeBtn.type = "button"
    removeBtn.className = "absolute -top-3 -right-3 z-10 w-6 h-6 bg-brand-light rounded-full text-white hover:bg-brand"
    removeBtn.innerHTML = "&times;"
    removeBtn.addEventListener("click", (e) => {
      e.preventDefault()
      e.stopPropagation()
      this.remove(entry)
    })
    wrapper.appendChild(removeBtn)

    this.previewContainerTarget.appendChild(wrapper)
  }

  videoFrame(file, callback) {
    const video = document.createElement("video")
    video.src = URL.createObjectURL(file)
    video.muted = true
    video.onloadedmetadata = () => { video.currentTime = video.duration * 0.1 }
    video.onseeked = () => {
      const canvas = document.createElement("canvas")
      canvas.width = video.videoWidth || 640
      canvas.height = video.videoHeight || 480
      canvas.getContext("2d").drawImage(video, 0, 0, canvas.width, canvas.height)
      callback(canvas.toDataURL("image/jpeg"))
      URL.revokeObjectURL(video.src)
      video.remove()
    }
  }

  // --- отрисовка состояния ---

  render() {
    const entries = [ ...this.uploads.values() ]
    entries.forEach(entry => this.renderEntry(entry))

    this.previewContainerTarget.classList.toggle("mt-3", entries.length > 0)
    this.progressContainerTarget.classList.toggle("hidden", entries.length === 0)

    const active = entries.filter(u => u.status !== "error")
    const totalBytes = active.reduce((sum, u) => sum + u.file.size, 0)
    const loadedBytes = active.reduce((sum, u) => sum + u.loaded, 0)
    const percent = totalBytes === 0 ? 0 : Math.floor((loadedBytes / totalBytes) * 100)
    const done = entries.filter(u => u.status === "done").length
    const failed = entries.length - active.length

    this.progressBarTarget.style.width = `${percent}%`
    this.progressPercentTarget.textContent = `${percent}%`

    if (this.pending().length > 0) {
      this.trackBatch(loadedBytes)
      this.progressStatusTarget.textContent =
        `Загружено ${done} из ${active.length} · ${this.formatMb(loadedBytes)} из ${this.formatMb(totalBytes)} МБ\n` +
        this.checkingText(active) +
        `Время загрузки ${this.formatDuration(this.elapsedSeconds())}\n` +
        this.etaText(loadedBytes, totalBytes)
      this.submitBtnTarget.disabled = true
      this.submitBtnTarget.value = `Загрузка ${percent}%...`
    } else {
      this.finishBatch()
      this.progressStatusTarget.textContent = failed > 0
        ? `✅ Загружено ${done}, с ошибкой ${failed}`
        : "✅ Все файлы загружены!"
      this.submitBtnTarget.disabled = done === 0
      this.submitBtnTarget.value = "Загрузить"
    }
  }

  renderEntry(entry) {
    entry.playIcon?.classList.toggle("hidden", entry.status !== "done")

    const marks = { done: [ "✓", "bg-green-500" ], error: [ "✗", "bg-red-500" ] }
    if (marks[entry.status]) {
      const [ symbol, color ] = marks[entry.status]
      entry.overlay.className = `absolute top-0 left-0 w-4 h-4 ${color} rounded-full text-white text-xs flex items-center justify-center`
      entry.overlay.textContent = symbol
    } else if (entry.status === "uploading") {
      this.overlayText(entry, `${Math.floor((entry.loaded / (entry.file.size || 1)) * 100)}%`)
    } else if (entry.status === "checking") {
      this.overlayText(entry, `Проверка\n${Math.floor((entry.checked / (entry.file.size || 1)) * 100)}%`)
    } else {
      this.overlayText(entry, "В очереди")
    }
  }

  // Надпись по центру превью, белым прямо по затемнению; \n — перенос, строки по центру, а не у левого края
  overlayText(entry, text) {
    let label = entry.overlay.firstElementChild
    if (!label) {
      label = document.createElement("span")
      label.className = "px-1 text-center leading-tight whitespace-pre-line"
      entry.overlay.replaceChildren(label)
    }
    label.textContent = text
  }

  // Пока не все файлы проверены — сколько проверено: иначе первые минуты на больших файлах ничего не движется
  checkingText(active) {
    const waiting = active.filter(u => u.status === "queued" || u.status === "checking")
    if (waiting.length === 0) return ""
    return `Проверено ${active.length - waiting.length} из ${active.length} файлов\n`
  }

  // --- оценка оставшегося времени ---

  // Серия начинается, когда появляются незавершённые загрузки, и заканчивается, когда их не остаётся.
  // Скорость — средняя за всю серию: она ровнее мгновенной и не скачет от каждого события progress
  trackBatch(loadedBytes) {
    if (this.batch) return
    this.batch = {
      startedAt: performance.now(),
      baseLoaded: loadedBytes, // файлы, загруженные до этой серии, в скорость не входят
      timer: setInterval(() => this.render(), 1000) // обновлять «Время загрузки/Осталось», даже если progress замер
    }
  }

  finishBatch() {
    clearInterval(this.batch?.timer)
    this.batch = null
  }

  elapsedSeconds() {
    return this.batch ? (performance.now() - this.batch.startedAt) / 1000 : 0
  }

  etaText(loadedBytes, totalBytes) {
    const elapsed = this.elapsedSeconds()
    const transferred = loadedBytes - this.batch.baseLoaded
    // Сначала файл проверяется (MD5) и создаётся blob: байты ещё не идут, скорости нет
    if (elapsed < 5 || transferred <= 0) return "Рассчитываем оставшееся время..."

    const remaining = (totalBytes - loadedBytes) / (transferred / elapsed)
    return `Осталось ~${this.formatDuration(remaining, { rough: true })}`
  }

  formatDuration(seconds, { rough = false } = {}) {
    const s = Math.max(0, Math.round(seconds))
    const h = Math.floor(s / 3600)
    const m = Math.floor((s % 3600) / 60)
    if (rough) {
      if (s < 60) return `${s} с`
      return h > 0 ? `${h} ч ${m} мин` : `${m + (s % 60 >= 30 ? 1 : 0)} мин`
    }
    const mm = String(m).padStart(h > 0 ? 2 : 1, "0")
    const ss = String(s % 60).padStart(2, "0")
    return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`
  }

  pending() {
    return [ ...this.uploads.values() ].filter(u => [ "queued", "checking", "uploading" ].includes(u.status))
  }

  appendHidden(name, values) {
    if (values.length === 0) return
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = values.join(",")
    this.formTarget.appendChild(input)
  }

  formatMb(bytes) {
    return (bytes / 1024 / 1024).toFixed(1)
  }

  showError(message) {
    const errorWrapper = document.createElement("div")
    errorWrapper.className = "mt-5 px-3 min-h-16 py-2 [overflow-wrap:anywhere] w-70 border border-danger text-danger bg-danger-bg rounded-lg flex items-center justify-center text-center"
    errorWrapper.textContent = message
    this.errorContainerTarget.appendChild(errorWrapper)
  }
}
