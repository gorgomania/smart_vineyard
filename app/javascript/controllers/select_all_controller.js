import { Controller } from "@hotwired/stimulus"

// Текст поля выделяется целиком, и новый набирается поверх старого.
// Поле переименования — при первом фокусе (его ставит autofocus), как в проводнике: дальше клик ставит курсор.
// Поиск (every-focus) — при каждом входе в поле, как адресная строка: в поле прошлый запрос, а набирают обычно новый.
// Второй клик по уже активному полю ставит курсор туда, куда нажали
export default class extends Controller {
  static values = { everyFocus: Boolean }

  connect() {
    this.select = () => {
      this.element.select()
      if (!this.everyFocusValue) this.element.removeEventListener("focus", this.select)
    }
    // Вход в поле кликом: после отпускания кнопки браузер ставит курсор в точку клика и снимает выделение.
    // Отменяем это один раз — только для клика, который поле и активировал
    this.rememberClick = () => { this.focusingClick = document.activeElement !== this.element }
    this.keepSelection = (event) => {
      if (this.focusingClick) event.preventDefault()
      this.focusingClick = false
    }

    this.element.addEventListener("mousedown", this.rememberClick)
    this.element.addEventListener("mouseup", this.keepSelection)
    this.element.addEventListener("focus", this.select)
    // Turbo ставит фокус по autofocus и до, и после подключения контроллера — ловим оба случая
    if (document.activeElement === this.element) this.select()
  }

  disconnect() {
    this.element.removeEventListener("mousedown", this.rememberClick)
    this.element.removeEventListener("mouseup", this.keepSelection)
    this.element.removeEventListener("focus", this.select)
  }
}
