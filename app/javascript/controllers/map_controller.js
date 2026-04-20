// app/javascript/controllers/map_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    // Получаем данные напрямую из атрибутов
    this.apiKey = this.element.dataset.mapApiKey
    this.center = this.parseCenter(this.element.dataset.mapCenter)
    this.zoom = parseInt(this.element.dataset.mapZoom) || 10
    this.enableDrawingOnLoad = this.element.dataset.mapDraw === 'true'
    this.currentRectangle = null

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
        type: 'yandex#hybrid',
        controls: ['zoomControl', 'fullscreenControl', 'geolocationControl']
      })

      this.element.__mapInstance = this.map
      
      // Создаем редактируемый прямоугольник
      this.currentRectangle = new ymaps.Rectangle(
          [[0, 0], [0, 0]],  // Временные координаты
          {
            hintContent: 'Виноградник',
            balloonContent: 'Перетащите углы для изменения размера'
          },
          {
            draggable: true,      // Можно перетаскивать
            editable: true,       // Включает режим редактирования
            fillColor: '#8BC34A',
            fillOpacity: 0.5,
            strokeColor: '#4CAF50',
            strokeWidth: 3,
            visible: false        // Сначала скрыт
          }
        )
      
      // Добавляем прямоугольник на карту
      this.map.geoObjects.add(this.currentRectangle)
      
      // Слушаем изменения геометрии
      this.currentRectangle.geometry.events.add('change', () => {
        this.saveRectangleBounds()
      })

      if (this.enableDrawingOnLoad) {
        setTimeout(() => {
          this.enableDrawing()
        }, 500)
      }

      this.map.events.add('boundschange', () => {
        this.dispatchMapUpdated()
      })
      
      this.map.events.add('zoomchange', () => {
        this.dispatchMapUpdated()
      })
      
      // Отправляем начальное состояние
      this.dispatchMapUpdated()
    })
  }

  enableDrawing() {
    console.log("Enabling drawing mode")
    
    if (!this.currentRectangle) {
      console.error("Rectangle not found")
      return
    }
    
    // Показываем прямоугольник
    this.currentRectangle.options.set('visible', true)
    
    // Сбрасываем координаты на нулевые
    const size = this.getRectangleSize()
    const center = this.center
    const northWest = [center[0] + size, center[1] - size]
    const southEast = [center[0] - size, center[1] + size]

    this.currentRectangle.geometry.setCoordinates([northWest, southEast])
    
    // Включаем режим редактирования
    if (this.currentRectangle.editor) {
      this.currentRectangle.editor.startEditing()
    }
    
    console.log("Drawing mode enabled - now you can drag the rectangle corners")
  }
  
  saveRectangleBounds() {
    if (!this.currentRectangle) return
    
    const bounds = this.currentRectangle.geometry.getBounds()
    
    // Проверяем, что прямоугольник не нулевой
    if (!bounds || bounds[0][0] === bounds[1][0] || bounds[0][1] === bounds[1][1]) {
      return
    }
    
    const northWest = bounds[0]  // [north_lat, west_lng]
    const southEast = bounds[1]  // [south_lat, east_lng]
    
    console.log("Rectangle bounds saved:", {
      north_lat: northWest[0],
      west_lng: northWest[1],
      south_lat: southEast[0],
      east_lng: southEast[1]
    })
    
    // Заполняем скрытые поля формы
    const northLatInput = document.getElementById('vineyard_north_lat')
    const southLatInput = document.getElementById('vineyard_south_lat')
    const eastLngInput = document.getElementById('vineyard_east_lng')
    const westLngInput = document.getElementById('vineyard_west_lng')
    
    if (northLatInput && southLatInput && eastLngInput && westLngInput) {
      northLatInput.value = northWest[0]
      westLngInput.value = northWest[1]
      southLatInput.value = southEast[0]
      eastLngInput.value = southEast[1]
    }
  }

  getRectangleSize() {
  // Размер в градусах в зависимости от зума
  // zoom: 10-19 (обычный диапазон)
    const sizeMap = {
      10: 0.05,  // ~5 км
      11: 0.03,  // ~3 км
      12: 0.02,  // ~2 км
      13: 0.01,  // ~1 км
      14: 0.005, // ~500 м
      15: 0.003, // ~300 м
      16: 0.002, // ~200 м
      17: 0.001, // ~100 м
      18: 0.0005,// ~50 м
      19: 0.0002 // ~20 м
    }
    
    return sizeMap[Math.round(this.zoom)] || 0.01
  }

  dispatchMapUpdated() {
    if (!this.map) return
    
    const center = this.map.getCenter()
    const zoom = this.map.getZoom()
    
    const event = new CustomEvent('map:updated', {
      detail: { center, zoom }
    })
    document.dispatchEvent(event)
  }
}