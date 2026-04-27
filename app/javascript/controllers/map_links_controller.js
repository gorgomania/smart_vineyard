import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]
  
  connect() {
    // Подписываемся на события от карты
    document.addEventListener('map:updated', (event) => {
      this.updateLinks(event.detail)
    })
    
    // Находим карту и получаем начальное состояние
    const mapElement = document.querySelector('[data-controller="map"]')
    if (mapElement && mapElement.__mapInstance) {
      this.updateLinks({
        center: mapElement.__mapInstance.getCenter(),
        zoom: mapElement.__mapInstance.getZoom()
      })
    }
  }
  
  updateLinks({ center, zoom }) {
    this.linkTargets.forEach(link => {
      const linkType = link.dataset.linkType
      if (linkType === 'create') {
        link.href = `/vineyards/new?center_lat=${center[0]}&center_lng=${center[1]}&zoom=${zoom}`
      } else if (linkType === 'list') {
        link.href = `/vineyards?center_lat=${center[0]}&center_lng=${center[1]}&zoom=${zoom}`
      }
    })
  }
}