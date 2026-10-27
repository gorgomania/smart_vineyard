import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

export default class extends Controller {
  static targets = [
    "fileInput", "dropZone", "previewContainer", "errorContainer",
    "progressContainer", "progressBar", "progressPercent", "progressStatus",
    "submitBtn", "form"
  ]

  connect() {
    this.uploadedBlobs = []
    this.pendingUploads = 0
    this.totalFiles = 0
  }

  fileInputChange(event) {
    event.preventDefault()
    event.stopPropagation()

    this.errorContainerTarget.innerHTML = ""
    this.previewContainerTarget.innerHTML = ""
    this.uploadedBlobs = []
    this.pendingUploads = 0
    this.totalFiles = 0
    this.progressContainerTarget.classList.add("hidden")
    this.progressBarTarget.style.width = "0%"

    const dataTransfer = new DataTransfer()
    const fileInput = this.fileInputTarget
    const filesToPreview = []

    for (let i = 0; i < fileInput.files.length; i++) {
      const file = fileInput.files[i]
      const isZip = file.name.toLowerCase().endsWith(".zip")
      const isSizeValid = file.size <= 1073741824

      if (isSizeValid) {
        const isValidType = isZip || file.type.startsWith("image/") || file.type.startsWith("video/")
        if (isValidType) {
          dataTransfer.items.add(file)
          filesToPreview.push(file)
        } else {
          this.showError("Недопустимый тип файла " + file.name)
        }
      } else {
        this.showError("Недопустимый размер файла " + file.name)
      }
    }
    fileInput.files = dataTransfer.files
    this.showPreview(filesToPreview)
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
    this.errorContainerTarget.innerHTML = ""
    event.preventDefault()
    event.stopPropagation()
    this.dropZoneTarget.classList.remove("border-purple-500", "bg-purple-100")
    this.addFilesWithCheckDuplicates(event.dataTransfer.files)
  }

  submit(event) {
    if (this.uploadedBlobs.length === 0) {
      event.preventDefault()
      this.showError("Нет загруженных файлов")
      return
    }
    const blobInput = document.createElement("input")
    blobInput.type = "hidden"
    blobInput.name = "signed_blob_ids"
    blobInput.value = this.uploadedBlobs.map(b => b.signed_id).join(",")
    this.formTarget.appendChild(blobInput)
  }

  addFilesWithCheckDuplicates(newFiles) {
    const dataTransfer = new DataTransfer()
    const fileInput = this.fileInputTarget
    const existingFiles = fileInput.files
    const existingFilesMap = new Map()

    for (let i = 0; i < existingFiles.length; i++) {
      existingFilesMap.set(`${existingFiles[i].name}_${existingFiles[i].size}`, true)
      dataTransfer.items.add(existingFiles[i])
    }

    const filesToPreview = []
    for (let i = 0; i < newFiles.length; i++) {
      const file = newFiles[i]
      const key = `${file.name}_${file.size}`
      const isZip = file.name.toLowerCase().endsWith(".zip")
      const isSizeValid = file.size <= 1073741824

      if (isSizeValid) {
        const isValidType = isZip || file.type.startsWith("image/") || file.type.startsWith("video/")
        if (isValidType) {
          if (!existingFilesMap.has(key)) {
            dataTransfer.items.add(file)
            filesToPreview.push(file)
          }
        } else {
          this.showError("Недопустимый тип файла " + file.name)
        }
      } else {
        this.showError("Недопустимый размер файла " + file.name)
      }
    }
    fileInput.files = dataTransfer.files
    this.showPreview(filesToPreview)
  }

  showPreview(files) {
    this.totalFiles += files.length
    this.progressContainerTarget.classList.remove("hidden")
    this.updateProgress()
    files.forEach(file => {
      const isZip = file.name.toLowerCase().endsWith(".zip")
      const isVideo = file.type.startsWith("video/")
      if (isZip) {
        this.createZipPreview(file)
      } else if (isVideo) {
        this.createVideoPreview(file)
      } else {
        this.createImagePreview(file)
      }
    })
  }

  createZipPreview(file) {
    const previewWrapper = document.createElement("div")
    previewWrapper.style.position = "relative"
    previewWrapper.className = "preview-item"

    const zipDiv = document.createElement("div")
    zipDiv.className = "w-full aspect-square bg-purple-50 rounded-lg border-2 border-purple-300 flex flex-col items-center justify-center"
    zipDiv.innerHTML = `
      <span class="text-xs text-[#4e4e4e] mt-2">ZIP архив</span>
      <span class="text-xs text-slate-500">${(file.size / 1024 / 1024).toFixed(2)} МБ</span>
    `

    const readyMark = document.createElement("div")
    readyMark.className = "absolute top-0 left-0 w-4 h-4 bg-green-500 rounded-full text-white text-xs flex items-center justify-center"
    readyMark.innerHTML = "✓"

    const removeBtn = document.createElement("button")
    removeBtn.className = "absolute -top-3 -right-3 z-10 w-6 h-6 bg-[#8a579f] rounded-full text-white hover:bg-[#69377c]"
    removeBtn.innerHTML = "&times;"

    removeBtn.addEventListener("click", (e) => {
      e.preventDefault()
      e.stopPropagation()

      const index = this.uploadedBlobs.findIndex(item => item.filename === file.name)
      if (index !== -1) this.uploadedBlobs.splice(index, 1)
      previewWrapper.remove()

      const dt = new DataTransfer()
      Array.from(this.fileInputTarget.files).forEach(f => {
        if (f.name !== file.name) dt.items.add(f)
      })
      this.fileInputTarget.files = dt.files

      this.totalFiles--
      this.updateProgress()
      if (this.previewContainerTarget.children.length === 0) {
        this.previewContainerTarget.classList.remove("mt-3")
      }
    })

    previewWrapper.appendChild(zipDiv)
    previewWrapper.appendChild(removeBtn)
    previewWrapper.appendChild(readyMark)

    this.uploadedBlobs.push({ signed_id: null, filename: file.name })
    this.previewContainerTarget.classList.add("mt-3")
    this.previewContainerTarget.appendChild(previewWrapper)
    this.updateProgress()
  }

  createImagePreview(file) {
    const reader = new FileReader()
    reader.onload = (e) => this.createPreviewWrapper(e.target.result, file)
    reader.readAsDataURL(file)
  }

  createVideoPreview(file) {
    const video = document.createElement("video")
    video.src = URL.createObjectURL(file)
    video.muted = true
    video.crossOrigin = "anonymous"
    video.onloadedmetadata = () => { video.currentTime = video.duration * 0.1 }
    video.onseeked = () => {
      const canvas = document.createElement("canvas")
      canvas.width = video.videoWidth || 640
      canvas.height = video.videoHeight || 480
      canvas.getContext("2d").drawImage(video, 0, 0, canvas.width, canvas.height)
      this.createPreviewWrapper(canvas.toDataURL("image/jpeg"), file)
      URL.revokeObjectURL(video.src)
      video.src = ""
      video.remove()
    }
  }

  createPreviewWrapper(url, file) {
    const previewWrapper = document.createElement("div")
    previewWrapper.style.position = "relative"

    const img = new Image()
    img.src = url

    const removeBtn = document.createElement("button")
    removeBtn.className = "absolute -top-3 -right-3 z-10 w-6 h-6 bg-[#8a579f] rounded-full text-white hover:bg-[#69377c]"
    removeBtn.innerHTML = "&times;"

    removeBtn.addEventListener("click", async (e) => {
      e.preventDefault()
      e.stopPropagation()

      const blobData = this.uploadedBlobs.find(item => item.filename === file.name)
      if (blobData) {
        const csrfToken = document.querySelector('[name="csrf-token"]').content
        await fetch(`/active_storage/blobs/${blobData.signed_id}`, {
          method: "DELETE",
          headers: { "X-CSRF-Token": csrfToken, "Content-Type": "application/json" }
        })
        this.uploadedBlobs = this.uploadedBlobs.filter(item => item.filename !== file.name)
      } else if (this.pendingUploads > 0) {
        this.pendingUploads--
      }

      this.totalFiles--
      this.updateProgress()
      previewWrapper.remove()

      const dt = new DataTransfer()
      Array.from(this.fileInputTarget.files).forEach(f => {
        if (f.name !== file.name) dt.items.add(f)
      })
      this.fileInputTarget.files = dt.files

      if (this.previewContainerTarget.children.length === 0) {
        this.previewContainerTarget.classList.remove("mt-3")
      }
    })

    previewWrapper.appendChild(img)
    previewWrapper.appendChild(removeBtn)

    if (file.type.startsWith("video/")) {
      const playIcon = new Image()
      playIcon.src = "/video_play_violet.png"
      playIcon.className = "w-3 h-3 absolute top-[14.5px] left-[35.5px]"
      previewWrapper.appendChild(playIcon)
    }

    img.onload = () => {
      this.previewContainerTarget.classList.add("mt-3")
      this.previewContainerTarget.appendChild(previewWrapper)
      this.startDirectUpload(file, previewWrapper)
    }
  }

  startDirectUpload(file, previewWrapper) {
    this.pendingUploads++
    this.submitBtnTarget.disabled = true
    this.submitBtnTarget.value = `Загрузка (${this.uploadedBlobs.length}/${this.totalFiles})...`

    const loadingIndicator = document.createElement("div")
    loadingIndicator.className = "absolute inset-0 bg-black/50 rounded-lg flex items-center justify-center text-white text-xs"
    loadingIndicator.innerHTML = "⏳ Загрузка..."
    previewWrapper.appendChild(loadingIndicator)

    const upload = new DirectUpload(file, "/rails/active_storage/direct_uploads")
    upload.create((error, blob) => {
      loadingIndicator.remove()
      if (error) {
        this.showError(`Ошибка загрузки "${file.name}": ${error.message || error}`)
        const errorMark = document.createElement("div")
        errorMark.className = "absolute top-0 left-0 w-4 h-4 bg-red-500 rounded-full text-white text-xs flex items-center justify-center"
        errorMark.innerHTML = "✗"
        previewWrapper.appendChild(errorMark)
      } else {
        this.uploadedBlobs.push({ signed_id: blob.signed_id, filename: file.name })
        const successMark = document.createElement("div")
        successMark.className = "absolute top-0 left-0 w-4 h-4 bg-green-500 rounded-full text-white text-xs flex items-center justify-center"
        successMark.innerHTML = "✓"
        previewWrapper.appendChild(successMark)
      }
      this.pendingUploads--
      this.updateProgress()
    })
  }

  updateProgress() {
    const completed = this.uploadedBlobs.length
    const percent = this.totalFiles === 0 ? 0 : Math.round((completed / this.totalFiles) * 100)

    this.progressPercentTarget.textContent = `${percent}%`
    this.progressBarTarget.style.width = `${percent}%`
    this.progressStatusTarget.textContent = `Загружено ${completed} из ${this.totalFiles} файлов`

    if (this.pendingUploads > 0) {
      this.submitBtnTarget.disabled = true
      this.submitBtnTarget.value = `Загрузка (${completed}/${this.totalFiles})...`
    } else if (this.pendingUploads === 0 && this.totalFiles > 0) {
      this.submitBtnTarget.disabled = false
      this.submitBtnTarget.value = "Загрузить"
      const status = completed === this.totalFiles
        ? "✅ Все файлы загружены!"
        : `✅ Загружено ${completed} из ${this.totalFiles} (с ошибками)`
      this.progressStatusTarget.textContent = status
    } else {
      this.submitBtnTarget.disabled = true
      this.submitBtnTarget.value = "Загрузить"
      this.progressContainerTarget.classList.add("hidden")
    }
  }

  showError(message) {
    const errorWrapper = document.createElement("div")
    errorWrapper.className = "mt-5 px-3 h-16 w-70 border border-red-800 text-red-800 bg-red-200 rounded-lg flex items-center justify-center text-center"
    errorWrapper.textContent = message
    this.errorContainerTarget.appendChild(errorWrapper)
  }
}
