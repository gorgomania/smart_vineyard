import { Controller } from "@hotwired/stimulus"

// Легенда тепловой карты: числа кустов по диагнозам приходят от map_controller (heatmap:counts),
// клик по строке прячет или показывает этот диагноз на карте (heatmap:filter)
export default class extends Controller {
  static targets = ["row", "count"]

  updateCounts({ detail: { counts } }) {
    this.countTargets.forEach(el => el.textContent = counts[el.dataset.diagnosis] ?? 0)
  }

  toggle({ currentTarget }) {
    currentTarget.setAttribute("aria-pressed", currentTarget.getAttribute("aria-pressed") === "false")

    const hidden = this.rowTargets
      .filter(row => row.getAttribute("aria-pressed") === "false")
      .map(row => row.dataset.diagnosis)
    document.dispatchEvent(new CustomEvent("heatmap:filter", { detail: { hidden } }))
  }

  // Свернуть или раскрыть на узком экране (классы max-[710px]: в разметке)
  toggleOpen() {
    this.element.toggleAttribute("data-open")
  }
}
