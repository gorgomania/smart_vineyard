import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]
  
  // Центр и зум приходят от карты (map:updated): при создании карты и при каждом сдвиге. До этого у ссылок
  // адреса из разметки. Подписку снимаем в disconnect, иначе после каждого перехода их становилось бы больше
  connect() {
    this.onMapUpdated = (event) => this.updateLinks(event.detail)
    document.addEventListener('map:updated', this.onMapUpdated)
  }

  disconnect() {
    document.removeEventListener('map:updated', this.onMapUpdated)
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