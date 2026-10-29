import { Controller } from "@hotwired/stimulus"

// Прячет скелетон-заглушку (.skeleton рядом с картинкой), когда картинка загрузилась.
// Вместо inline onload, который блокирует CSP
export default class extends Controller {
  connect() {
    // Из кеша картинка может загрузиться раньше, чем подключится контроллер
    if (this.element.complete && this.element.naturalWidth > 0) this.hide()
  }

  hide() {
    this.element.parentElement.querySelector(".skeleton")?.classList.add("hidden")
  }
}
