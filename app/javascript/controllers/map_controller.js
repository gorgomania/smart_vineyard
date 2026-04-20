// app/javascript/controllers/map_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    // Получаем данные напрямую из атрибутов
    this.apiKey = this.element.dataset.mapApiKey
    this.center = this.parseCenter(this.element.dataset.mapCenter)
    this.zoom = parseInt(this.element.dataset.mapZoom) || 10
    this.enableDrawingOnLoad = this.element.dataset.mapDraw === 'true'
    this.currentPolygon = null

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
      const size = this.getRectangleSize()
      const center = this.center
      this.currentPolygon = new ymaps.Polygon(
        [[
          [center[0] + size, center[1] - size],  // северо-запад
          [center[0] + size, center[1] + size],  // северо-восток
          [center[0] - size, center[1] + size],  // юго-восток
          [center[0] - size, center[1] - size],  // юго-запад
          [center[0] + size, center[1] - size]   // замыкаем
        ]],
        {
          hintContent: 'Виноградник',
          balloonContent: 'Перетащите углы для изменения размера'
        },
        {
          draggable: true,      // Можно перетаскивать
          editable: true,       // Включает режим редактирования
          fillColor: '#8a579f',
          fillOpacity: 0.5,
          strokeColor: '#69377c',
          strokeWidth: 3,
          visible: false,             // Сначала скрыт
          editorDrawing: false,      
          editorMaxPoints: 4       // Отключает режим добавления новых вершин
        }
      )
      
      // Добавляем прямоугольник на карту
      this.map.geoObjects.add(this.currentPolygon)
      
      // Слушаем изменения геометрии
      this.currentPolygon.geometry.events.add('change', () => {
          const coordinates = this.currentPolygon.geometry.getCoordinates()[0]
          const event = new CustomEvent('map:polygonUpdated', {
            detail: { coordinates: coordinates }
          })
          document.dispatchEvent(event)
      })

      // Подписываемся на события от формы
      document.addEventListener('form:polygonUpdated', (event) => {
        if (this.currentPolygon) {
          this.currentPolygon.geometry.setCoordinates(event.detail.bounds)
        }
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
    
    if (!this.currentPolygon) {
      console.error("Polygon not found")
      return
    }
    
    // Показываем прямоугольник
    this.currentPolygon.options.set('visible', true)

    // Обновляем координаты под текущий центр карты
    const size = this.getRectangleSize()
    const center = this.map.getCenter()
    this.currentPolygon.geometry.setCoordinates([[
      [center[0] + size, center[1] - size],
      [center[0] + size, center[1] + size],
      [center[0] - size, center[1] + size],
      [center[0] - size, center[1] - size],
      [center[0] + size, center[1] - size]
    ]])

    // Включаем режим редактирования
    if (this.currentPolygon.editor) {
      this.currentPolygon.editor.startEditing()
    }
  }

  getRectangleSize() {
    const sizeMap = {
      10: 0.05, 11: 0.03, 12: 0.02, 13: 0.01,
      14: 0.005, 15: 0.003, 16: 0.002, 17: 0.001,
      18: 0.0005, 19: 0.0002
    }
    const currentZoom = this.map ? this.map.getZoom() : this.zoom
    return sizeMap[Math.round(currentZoom)] || 0.01
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