import { Controller } from "@hotwired/stimulus"

// Поле переименования: при первом фокусе (его ставит autofocus) текущее имя выделяется целиком, и новое
// набирается поверх, как в проводнике. Только в первый раз: дальше клик ставит курсор туда, куда нажали
export default class extends Controller {
  connect() {
    this.select = () => this.element.select()
    // Turbo ставит фокус по autofocus и до, и после подключения контроллера — ловим оба случая
    if (document.activeElement === this.element) this.select()
    else this.element.addEventListener("focus", this.select, { once: true })
  }

  disconnect() {
    this.element.removeEventListener("focus", this.select)
  }
}
