// app/javascript/controllers/map_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Получаем данные напрямую из атрибутов
    this.apiKey = this.element.dataset.mapApiKey
    this.center = this.parseCenter(this.element.dataset.mapCenter)
    this.zoom = parseInt(this.element.dataset.mapZoom) || 10
    
    if (!this.apiKey) {
      console.error('Map API key is missing')
      return
    }
    
    this.loadMap()
  }
  
  parseCenter(centerStr) {
    if (!centerStr) return [55.76, 37.64]
    try {
      // Парсим строку вида "[55.76, 37.64]"
      return JSON.parse(centerStr)
    } catch(e) {
      return [55.76, 37.64]
    }
  }
  
  loadMap() {
    // Проверяем, не загружено ли уже API
    if (window.ymaps) {
      this.initMap()
      return
    }
    
    // Загружаем API
    const script = document.createElement('script')
    script.src = `https://api-maps.yandex.ru/2.1/?apikey=${this.apiKey}&lang=ru_RU`
    script.onload = () => this.initMap()
    script.onerror = () => console.error('Failed to load Yandex Maps API')
    document.head.appendChild(script)
  }
  
  initMap() {
    ymaps.ready(() => {
      this.map = new ymaps.Map(this.element, {
        center: this.center,
        zoom: this.zoom,
        controls: ['zoomControl', 'fullscreenControl', 'geolocationControl']
      })
      
      // Добавляем маркер в центр
      const placemark = new ymaps.Placemark(this.center, {
        hintContent: 'СевГУ',
        balloonContent: 'Это самый лучший ВУЗ!'
      })
      
      this.map.geoObjects.add(placemark)
      console.log('Map initialized successfully')
    })
  }
}