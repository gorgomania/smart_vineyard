import { Controller } from "@hotwired/stimulus"

// Мигающий скелетон под превью: прячем его, когда картинка загрузилась
// (сама картинка его не закрывает, если у неё прозрачный фон).
// data-loaded ставим здесь, а refresh-морфинг (Folder#broadcast_new_files) снял бы его,
// потому что в серверном HTML его нет, — поэтому не даём морфингу его трогать
export default class extends Controller {
  static targets = ["image"]

  connect() {
    this.keepLoaded = event => {
      if (event.target === this.element && event.detail.attributeName === "data-loaded") event.preventDefault()
    }
    this.element.addEventListener("turbo:before-morph-attribute", this.keepLoaded)
  }

  disconnect() {
    this.element.removeEventListener("turbo:before-morph-attribute", this.keepLoaded)
  }

  // Картинка могла загрузиться раньше, чем подключился контроллер (из кэша)
  imageTargetConnected(image) {
    if (image.complete && image.naturalWidth) this.loaded()
  }

  loaded() {
    this.element.setAttribute("data-loaded", "")
  }
}
