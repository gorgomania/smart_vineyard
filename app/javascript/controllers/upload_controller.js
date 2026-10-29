import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

const MAX_FILE_SIZE = 1073741824 // 1 ГБ
const DIRECT_UPLOAD_URL = "/rails/active_storage/direct_uploads"

// Все файлы (включая ZIP) сразу грузятся через DirectUpload, прогресс считается по байтам.
// При отправке формы уходят только signed id: сами файлы второй раз не передаются
export default class extends Controller {
  static targets = [
    "fileInput", "dropZone", "previewContainer", "errorContainer",
    "progressContainer", "progressBar", "progressPercent", "progressStatus",
    "submitBtn", "form"
  ]

  connect() {
    // ключ name_size → { file, isZip, loaded, status: preparing|uploading|done|error, signedId, xhr, wrapper, overlay }
    this.uploads = new Map()
    this.render()
  }

  fileInputChange(event) {
    event.preventDefault()
    this.errorContainerTarget.innerHTML = ""
    this.addFiles(this.fileInputTarget.files)
    // Чтобы повторный выбор того же файла снова вызвал change
    this.fileInputTarget.value = ""
  }

  dragOver(event) {
    event.preventDefault()
    event.stopPropagation()
    this.dropZoneTarget.classList.add("border-purple-500", "bg-purple-100")
  }

  dragLeave() {
    this.dropZoneTarget.classList.remove("border-purple-500", "bg-purple-100")
  }

  drop(event) {
    event.preventDefault()
    event.stopPropagation()
    this.errorContainerTarget.innerHTML = ""
    this.dropZoneTarget.classList.remove("border-purple-500", "bg-purple-100")
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

      const entry = { key, file, isZip, loaded: 0, status: "preparing", signedId: null, xhr: null }
      this.uploads.set(key, entry)
      this.buildPreview(entry)
      this.startUpload(entry)
    })
    this.render()
  }

  startUpload(entry) {
    const upload = new DirectUpload(entry.file, DIRECT_UPLOAD_URL, {
      directUploadWillStoreFileWithXHR: (xhr) => {
        entry.xhr = xhr
        entry.status = "uploading"
        xhr.upload.addEventListener("progress", (e) => {
          entry.loaded = e.loaded
          this.render()
        })
        this.render()
      }
    })

    upload.create((error, blob) => {
      if (!this.uploads.has(entry.key)) return // удалён пользователем во время загрузки

      if (error) {
        entry.status = "error"
        this.showError(`Ошибка загрузки "${entry.file.name}": ${error.message || error}`)
      } else {
        entry.status = "done"
        entry.loaded = entry.file.size
        entry.signedId = blob.signed_id
      }
      this.render()
    })
  }

  remove(entry) {
    this.uploads.delete(entry.key)
    entry.wrapper.remove()

    if (entry.status === "uploading") {
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
      tile.className = "w-full aspect-square bg-purple-50 rounded-lg border-2 border-purple-300 flex flex-col items-center justify-center"
      tile.innerHTML = `
        <span class="text-xs text-[#4e4e4e] mt-2">ZIP архив</span>
        <span class="text-xs text-slate-500">${this.formatMb(entry.file.size)} МБ</span>
      `
      wrapper.appendChild(tile)
    } else {
      const img = new Image()
      img.className = "w-full aspect-square object-cover rounded-lg"
      wrapper.appendChild(img)
      if (entry.file.type.startsWith("video/")) {
        this.videoFrame(entry.file, url => { img.src = url })
        const playIcon = new Image()
        playIcon.src = "/video_play_violet.png"
        playIcon.className = "w-3 h-3 absolute top-[14.5px] left-[35.5px]"
        wrapper.appendChild(playIcon)
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
    removeBtn.className = "absolute -top-3 -right-3 z-10 w-6 h-6 bg-[#8a579f] rounded-full text-white hover:bg-[#69377c]"
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
      this.progressStatusTarget.textContent =
        `Загружено ${done} из ${active.length} · ${this.formatMb(loadedBytes)} из ${this.formatMb(totalBytes)} МБ`
      this.submitBtnTarget.disabled = true
      this.submitBtnTarget.value = `Загрузка ${percent}%...`
    } else {
      this.progressStatusTarget.textContent = failed > 0
        ? `✅ Загружено ${done}, с ошибкой ${failed}`
        : "✅ Все файлы загружены!"
      this.submitBtnTarget.disabled = done === 0
      this.submitBtnTarget.value = "Загрузить"
    }
  }

  renderEntry(entry) {
    const marks = { done: [ "✓", "bg-green-500" ], error: [ "✗", "bg-red-500" ] }
    if (marks[entry.status]) {
      const [ symbol, color ] = marks[entry.status]
      entry.overlay.className = `absolute top-0 left-0 w-4 h-4 ${color} rounded-full text-white text-xs flex items-center justify-center`
      entry.overlay.textContent = symbol
    } else if (entry.status === "uploading") {
      entry.overlay.textContent = `${Math.floor((entry.loaded / (entry.file.size || 1)) * 100)}%`
    } else {
      entry.overlay.textContent = "Подготовка..." // считается checksum и создаётся blob
    }
  }

  pending() {
    return [ ...this.uploads.values() ].filter(u => u.status === "preparing" || u.status === "uploading")
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
    errorWrapper.className = "mt-5 px-3 h-16 w-70 border border-red-800 text-red-800 bg-red-200 rounded-lg flex items-center justify-center text-center"
    errorWrapper.textContent = message
    this.errorContainerTarget.appendChild(errorWrapper)
  }
}
