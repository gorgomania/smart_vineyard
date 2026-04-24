// app/javascript/controllers/map_controller.js
import { Controller } from "@hotwired/stimulus"
import { GeometryHelpers } from "utils/geometry_helpers"

export default class extends Controller {

  connect() {
    // Получаем данные напрямую из атрибутов
    this.apiKey = this.element.dataset.mapApiKey
    this.center = this.parseCenter(this.element.dataset.mapCenter)
    this.zoom = parseInt(this.element.dataset.mapZoom) || 10
    this.enableDrawingOnLoad = this.element.dataset.mapDraw === 'true'
    this.currentPolygon = null
    this.rowsCollection = null
    this.bushesCollection = null
    this.rowSpacing = 3.0
    this.bushSpacing = 1.5

    if (!this.apiKey) {
      console.error('Map API key is missing')
      return
    }
    
    this.loadMap()
  }
  
  parseCenter(centerStr) {
    if (!centerStr) return [44.5947, 33.4756]
    try {
      return JSON.parse(centerStr)
    } catch(e) {
      return [44.5947, 33.4756]
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
      
      // Создаем объект прямоугольника
      this.currentPolygon = new ymaps.Polygon(
        [[]],
        {
          hintContent: 'Виноградник',
          balloonContent: 'Перетащите углы для изменения размера'
        },
        {
          draggable: true,      // Можно перетаскивать
          editable: true,       // Включает режим редактирования
          fillColor: '#8a579f',
          fillOpacity: 0.1,
          strokeColor: '#69377c',
          strokeWidth: 3,
          visible: false,             // Сначала скрыт
          editorDrawing: false,      
          editorMaxPoints: 4       // Отключает режим добавления новых вершин
        }
      )
      
      // Добавляем прямоугольник на карту
      this.map.geoObjects.add(this.currentPolygon)
      
      // Создаем коллекции для рядов и кустов
      this.rowsCollection = new ymaps.GeoObjectCollection({}, {
        strokeColor: '#69377c',
        strokeWidth: 2,
        strokeOpacity: 0.8
      })
      
      this.bushesCollection = new ymaps.GeoObjectCollection({}, {
        iconLayout: 'default#image',
        iconImageHref: 'data:image/svg+xml,' + encodeURIComponent(`
          <svg width="4" height="4" xmlns="http://www.w3.org/2000/svg">
            <circle cx="2" cy="2" r="2" fill="#2ECC40"/>
          </svg>
        `),
        iconImageSize: [4, 4],
        iconImageOffset: [-2, -2]
      })
      
      this.map.geoObjects.add(this.rowsCollection)
      this.map.geoObjects.add(this.bushesCollection)

      // Слушаем изменения геометрии
      this.currentPolygon.geometry.events.add('change', () => {
          const coordinates = this.currentPolygon.geometry.getCoordinates()[0]
          this.generateRows(coordinates)
          const event = new CustomEvent('map:polygonUpdated', {
            detail: { coordinates: coordinates }
          })
          document.dispatchEvent(event)
      })

      // Подписываемся на события от формы
      document.addEventListener('form:polygonUpdated', (event) => {
        if (this.currentPolygon) {
          this.currentPolygon.geometry.setCoordinates(event.detail.coordinates)
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
    const Coords = [[
      [center[0] + size, center[1] - size],
      [center[0] + size, center[1] + size],
      [center[0] - size, center[1] + size],
      [center[0] - size, center[1] - size],
      [center[0] + size, center[1] - size]
    ]]

    this.currentPolygon.geometry.setCoordinates(Coords)

    // Включаем режим редактирования
    if (this.currentPolygon.editor) {
      this.currentPolygon.editor.startEditing()
    }
  }

  generateRows(polygonPoints) {
    if (!polygonPoints || polygonPoints.length < 4) return
    
    // Очищаем предыдущие отрисовки
    this.rowsCollection.removeAll()
    // this.bushesCollection.removeAll()
    // Находим самую длинную сторону для определения направления рядов
    const sides = this.getPolygonSides(polygonPoints)
    const longestSide = sides.reduce((max, side) => 
      side.length > max.length ? side : max, sides[0]
    )
    
    // Ряды будут параллельны самой длинной стороне
    const rowDirection = [longestSide.p2[0] - longestSide.p1[0], longestSide.p2[1] - longestSide.p1[1]]
    
    // Рассчитываем перпендикулярное направление
    const perpDirection = [-rowDirection[1], rowDirection[0]]
    
    // Нормализуем перпендикулярное направление
    const perpLength = Math.sqrt(perpDirection[0]**2 + perpDirection[1]**2)
    const perpUnit = [perpDirection[0] / perpLength, perpDirection[1] / perpLength]
    
    // Рассчитываем ширину участка в перпендикулярном направлении
    const width = this.calculateWidth(polygonPoints, perpUnit)
    const rowSpacingDeg = this.metersToDegrees(this.rowSpacing)
    
    // Количество рядов
    const numRows = Math.floor(width / rowSpacingDeg)
    
    // Находим опорную точку
    const referencePoint = this.findReferencePoint(polygonPoints, perpUnit)
    let totalBushes = 0;
    // Генерируем ряды
    for (let i = 0; i <= numRows; i++) {
      const offset = i * rowSpacingDeg
      const linePoints = this.getRowLine(polygonPoints, perpUnit, referencePoint, offset, rowDirection)
      if (linePoints.length >= 2) {
        // Добавляем линию ряда
        const rowLine = new ymaps.Polyline(
          linePoints.map(p => [p[0], p[1]]),
          { hintContent: `Ряд ${i + 1}` }
        )
        this.rowsCollection.add(rowLine)
        const rowLengthMeters = this.calculateLineLengthKm(linePoints[0], linePoints[linePoints.length-1]) * 1000
        // Прибавляем количество кустов
        totalBushes += Math.floor(rowLengthMeters / this.bushSpacing)
      }
    }
    
    const areaInHectares = GeometryHelpers.calculateArea(polygonPoints)
    this.sendStatisticsToForm(numRows + 1, totalBushes, areaInHectares)
  }

  getPolygonSides(points) {
    const sides = []
    for (let i = 0; i < points.length - 1; i++) {
      sides.push({
        p1: points[i],
        p2: points[i + 1],
        length: this.distance(points[i], points[i + 1])
      })
    }
    return sides
  }

  generateBushesOnRow(linePoints, rowIndex) {
    if (linePoints.length < 2) return
    
    // Длина ряда в метрах
    const rowLengthMeters = this.calculateLineLengthKm(linePoints[0], linePoints[linePoints.length-1]) * 1000
    
    // Количество кустов
    const numBushes = Math.floor(rowLengthMeters / this.bushSpacing)
    
    for (let i = 0; i <= numBushes; i++) {
      const t = i / numBushes // Пропорция вдоль ряда
      
      // Интерполяция позиции куста
      const bushPoint = this.interpolateOnLine(linePoints, t)
      
      if (bushPoint && this.isPointInPolygon(bushPoint, linePoints[0], linePoints[linePoints.length-1])) {
        // Добавляем куст
        const bush = new ymaps.Placemark(
          [bushPoint[0], bushPoint[1]],
          { 
            hintContent: `Ряд ${rowIndex + 1}, Куст ${i + 1}`,
          }
        )
        this.bushesCollection.add(bush)
      }
    }
  }

  distance(p1, p2) {
    return Math.sqrt((p1[0] - p2[0])**2 + (p1[1] - p2[1])**2)
  }

  metersToDegrees(meters) {
    // Примерное преобразование: 1 градус ≈ 111 км на экваторе
    // Для более точного вычисления нужно учитывать широту
    return meters / 111000
  }

  calculateWidth(polygonPoints, direction) {
    const projections = polygonPoints.map(p => 
      p[0] * direction[0] + p[1] * direction[1]
    )
    return Math.max(...projections) - Math.min(...projections)
  }

  findReferencePoint(polygonPoints, direction) {
    const projections = polygonPoints.map(p => 
      p[0] * direction[0] + p[1] * direction[1]
    )
    const minIndex = projections.indexOf(Math.min(...projections))
    return polygonPoints[minIndex]
  }

  getRowLine(polygonPoints, perpUnit, referencePoint, offset, rowDirection) {
    // Находим пересечения линии с границами полигона
    const lineStart = [
      referencePoint[0] + perpUnit[0] * offset,
      referencePoint[1] + perpUnit[1] * offset
    ]
    
    const intersections = []
    for (let i = 0; i < polygonPoints.length - 1; i++) {
      const intersection = this.lineIntersection(
        lineStart,
        [lineStart[0] + rowDirection[0], lineStart[1] + rowDirection[1]],
        polygonPoints[i],
        polygonPoints[i + 1]
      )
      if (intersection) {
        intersections.push(intersection)
      }
    }
    return intersections.sort((a, b) => this.distance(lineStart, a) - this.distance(lineStart, b))
  }
  
  lineIntersection(p1, p2, p3, p4) {
    const denominator = (p4[1] - p3[1]) * (p2[0] - p1[0]) - (p4[0] - p3[0]) * (p2[1] - p1[1])
    if (denominator === 0) return null
    const ua = ((p4[0] - p3[0]) * (p1[1] - p3[1]) - (p4[1] - p3[1]) * (p1[0] - p3[0])) / denominator
    const ub = ((p2[0] - p1[0]) * (p1[1] - p3[1]) - (p2[1] - p1[1]) * (p1[0] - p3[0])) / denominator
    
    if (ua < 0 || ua > 1 || ub < 0 || ub > 1) return null
    
    return [
      p1[0] + ua * (p2[0] - p1[0]),
      p1[1] + ua * (p2[1] - p1[1])
    ]
  }

  calculateLineLengthKm(p1, p2) {
    return GeometryHelpers.distance(p1, p2)
  }

  interpolateOnLine(points, t) {
    if (points.length < 2) return null
    
    const totalLength = this.getLineLength(points)
    const targetLength = totalLength * t
    
    let accumulatedLength = 0
    for (let i = 0; i < points.length - 1; i++) {
      const segmentLength = this.distance(points[i], points[i + 1])
      if (accumulatedLength + segmentLength >= targetLength) {
        const remaining = targetLength - accumulatedLength
        const ratio = remaining / segmentLength
        return [
          points[i][0] + (points[i + 1][0] - points[i][0]) * ratio,
          points[i][1] + (points[i + 1][1] - points[i][1]) * ratio
        ]
      }
      accumulatedLength += segmentLength
    }
    
    return points[points.length - 1]
  }

  getLineLength(points) {
    let length = 0
    for (let i = 0; i < points.length - 1; i++) {
      length += this.distance(points[i], points[i + 1])
    }
    return length
  }

  isPointInPolygon(point, startPoint, endPoint) {
    // Упрощенная проверка - можно расширить для более точной
    return true
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

  sendStatisticsToForm(rowsCount, bushesCount, areaInHectares) {
  // Отправляем событие с данными о рядах и кустах
    const event = new CustomEvent('map:statisticsUpdated', {
      detail: { 
        rows: rowsCount,
        bushes: bushesCount,
        area: areaInHectares.toFixed(2)
      }
    })
    document.dispatchEvent(event)
  }
}