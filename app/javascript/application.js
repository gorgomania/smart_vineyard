import { Turbo } from "@hotwired/turbo-rails"
import "controllers"

// Файл куста классифицирован (MediaItem#broadcast_diagnosis): отдаём данные карте, она перекрасит точку
Turbo.StreamActions.heatmap_bush = function () {
  const detail = {
    bush: this.getAttribute("bush"),
    mediaItemId: this.getAttribute("media-item-id"),
    classId: this.getAttribute("class-id")
  }
  this.targetElements.forEach(el => el.dispatchEvent(new CustomEvent("heatmap:bush", { detail })))
}

// Привязки файлов к кустам поменялись (Vineyard.broadcast_diagnoses_changed): карта перечитывает диагнозы целиком
Turbo.StreamActions.heatmap_refresh = function () {
  this.targetElements.forEach(el => el.dispatchEvent(new CustomEvent("heatmap:refresh")))
}

document.addEventListener("turbo:load", () => {
  document.querySelectorAll(".flash").forEach(el => {
    setTimeout(() => {
      el.style.opacity = "0"
      setTimeout(() => el.remove(), 500)
    }, 3000)
  })
})
