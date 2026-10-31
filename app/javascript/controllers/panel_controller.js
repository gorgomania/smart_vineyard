import { Controller } from "@hotwired/stimulus"

// На экранах < 1000px боковая панель скрыта и открывается поверх карты по кнопке.
// Видимость задаётся классами group-data-[open]: в разметке, здесь только флаг.
export default class extends Controller {
  toggle() {
    this.element.toggleAttribute("data-open")
  }
}
