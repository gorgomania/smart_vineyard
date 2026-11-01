import { Controller } from "@hotwired/stimulus"

// Легенда тепловой карты: числа кустов по диагнозам приходят от map_controller (heatmap:counts),
// клик по строке прячет или показывает этот диагноз на карте (heatmap:filter)
export default class extends Controller {
  static targets = ["row", "count", "list", "toggle"]

  updateCounts({ detail: { counts } }) {
    this.countTargets.forEach(el => el.textContent = counts[el.dataset.diagnosis] ?? 0)
  }

  toggle({ currentTarget }) {
    const shown = currentTarget.getAttribute("aria-pressed") === "false"
    currentTarget.setAttribute("aria-pressed", shown)
    currentTarget.title = `${shown ? "Скрыть" : "Показать"} «${currentTarget.dataset.name}» на карте`

    const hidden = this.rowTargets
      .filter(row => row.getAttribute("aria-pressed") === "false")
      .map(row => row.dataset.diagnosis)
    document.dispatchEvent(new CustomEvent("heatmap:filter", { detail: { hidden } }))
  }

  // Свернуть или раскрыть. Пока не нажимали, состояние задаёт ширина экрана (max-[710px]: в разметке),
  // поэтому смотрим, видна ли легенда сейчас, и ставим противоположное
  toggleOpen() {
    this.element.dataset.state = this.open ? "closed" : "open"
    this.updateToggleTitle()
  }

  // Подсказка — то, что сделает клик сейчас. Обновляем при наведении: состояние по умолчанию меняется с шириной окна
  updateToggleTitle() {
    this.toggleTarget.title = this.open ? "Свернуть легенду" : "Раскрыть легенду"
  }

  get open() {
    return getComputedStyle(this.listTarget).display !== "none"
  }
}
