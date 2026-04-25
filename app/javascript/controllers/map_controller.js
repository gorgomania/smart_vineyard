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
    this.referenceSideIndex = 0
    this.referenceVertexIsFirst = true

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

      // Слушаем изменения расстояния между рядами и кустами
      document.addEventListener('vineyard:spacingChanged', (event) => {
        this.rowSpacing = event.detail.rowSpacing
        this.bushSpacing = event.detail.bushSpacing
        
        // Перегенерируем ряды с новыми параметрами
        this.regenerateRows()
      })

      // Слушаем изменения опорной стороны
      document.addEventListener('vineyard:prevSide', () => {
        this.switchToPreviousSide()
      })

      document.addEventListener('vineyard:nextSide', () => {
        this.switchToNextSide()
      })

      document.addEventListener('vineyard:firstBushChanged', () => {
        this.referenceVertexIsFirst = !this.referenceVertexIsFirst
        this.regenerateRows()
      })

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

  switchToPreviousSide() {
    const coordinates = this.currentPolygon.geometry.getCoordinates()[0]
    if (this.referenceSideIndex - 1 >= 0) {
      this.referenceSideIndex -= 1
    }
    else {
      this.referenceSideIndex = coordinates.length - 2
    }
    this.generateRows(coordinates)
  }

  switchToNextSide() {
    const coordinates = this.currentPolygon.geometry.getCoordinates()[0]
    if (this.referenceSideIndex + 1 <= coordinates.length - 2) {
      this.referenceSideIndex += 1
    }
    else {
      this.referenceSideIndex = 0
    }
    this.generateRows(coordinates)
  }

  regenerateRows() {
    if (!this.currentPolygon) return
  
    const coordinates = this.currentPolygon.geometry.getCoordinates()[0]
    if (coordinates && coordinates.length >= 3) {
      this.generateRows(coordinates)
    }
  }

  generateRows(polygonPoints) {
    if (!polygonPoints || polygonPoints.length < 3) return
    
    this.rowsCollection.removeAll()
    
    // 1. Находим самую длинную сторону (первый ряд)
    const firstRow = this.getPolygonSide(polygonPoints)

    // 2. Добавляем первый ряд
    let totalBushes = this.addRow(firstRow.p1, firstRow.p2, 1, true)
    // 3. Направление перпендикуляра (смещение рядов)
    const rowVector = [firstRow.p2[0] - firstRow.p1[0], firstRow.p2[1] - firstRow.p1[1]]
    const perpVector = [-rowVector[1], rowVector[0]] // Поворот на 90°
    
    // Нормализуем перпендикуляр
    const perpLength = Math.sqrt(perpVector[0]**2 + perpVector[1]**2)
    const perpUnit = [perpVector[0] / perpLength, perpVector[1] / perpLength]
    
    // Шаг смещения в градусах
    const stepDeg = this.metersToDegrees(this.rowSpacing)
    
    // 4. Генерируем ряды в обе стороны
    let offset = stepDeg
    let hasNextRow = true
    let numRows = 1
    
    // В одну сторону
    while (hasNextRow) {
      const shiftedRow = this.shiftLine(firstRow.p1, firstRow.p2, perpUnit, offset)
      const intersections = this.getIntersectionsWithPolygon(shiftedRow.p1, shiftedRow.p2, polygonPoints)
      if (intersections.length === 2) {
        numRows += 1
        totalBushes += this.addRow(intersections[0], intersections[1], numRows)
        offset += stepDeg
      } else {
        hasNextRow = false
      }
    }
    // В другую сторону
    offset = -stepDeg
    hasNextRow = true
    while (hasNextRow) {
      const shiftedRow = this.shiftLine(firstRow.p1, firstRow.p2, perpUnit, offset)
      const intersections = this.getIntersectionsWithPolygon(shiftedRow.p1, shiftedRow.p2, polygonPoints)
      if (intersections.length === 2) {
        numRows += 1
        totalBushes += this.addRow(intersections[0], intersections[1], numRows)
        offset -= stepDeg
      } else {
        hasNextRow = false
      }
    }
    
    const areaInHectares = GeometryHelpers.calculateArea(polygonPoints)
    this.sendStatisticsToForm(numRows, totalBushes, areaInHectares)
  }

  // Смещение линии
  shiftLine(p1, p2, perpUnit, offset) {
    return {
      p1: [p1[0] + perpUnit[0] * offset, p1[1] + perpUnit[1] * offset],
      p2: [p2[0] + perpUnit[0] * offset, p2[1] + perpUnit[1] * offset]
    }
  }

  // Поиск пересечений линии с полигоном
  getIntersectionsWithPolygon(lineP1, lineP2, polygonPoints) {
    const intersections = []

    for (let i = 0; i < polygonPoints.length - 1; i++) {
      const intersection = this.lineIntersection(
        lineP1, lineP2,
        polygonPoints[i], polygonPoints[i + 1]
      )

      if (intersection) {
        intersections.push(intersection)
      }
    }
    
    return intersections.sort((a, b) => this.distance(lineP1, a) - this.distance(lineP1, b))
  }

  // Добавление ряда (только линия, без кустов)
  addRow(p1, p2, rowNumber, isFirstRow = false) {
    // Вычисляем количество кустов
    const rowLengthMeters = this.calculateLineLengthKm(p1, p2) * 1000
    const numBushes = Math.floor(rowLengthMeters / this.bushSpacing)
    // Склонение слова "куст"
    let bushesText = ''
    if (numBushes % 10 === 1 && numBushes % 100 !== 11) {
      bushesText = `${numBushes} куст`
    } else if ([2, 3, 4].includes(numBushes % 10) && ![12, 13, 14].includes(numBushes % 100)) {
      bushesText = `${numBushes} куста`
    } else {
      bushesText = `${numBushes} кустов`
    }
    let rowLine
    if (!isFirstRow) {
      rowLine = new ymaps.Polyline(
      [[p1[0], p1[1]], [p2[0], p2[1]]],
      { 
        hintContent: `Ряд ${rowNumber} · ${bushesText}`,
      }
    )
    }
    else {
      rowLine = new ymaps.Polyline(
      [[p1[0], p1[1]], [p2[0], p2[1]]],
      { 
        hintContent: `Ряд ${rowNumber} · ${bushesText}`,
      },
      {
        strokeColor: '#FFD700',  // Золотой для первого ряда
        strokeWidth: 4,
        strokeOpacity: 0.9
      })
      let p
      if (this.referenceVertexIsFirst) {
        p = p1
      }
      else {
        p = p2
      }
      const startCircle = new ymaps.Circle(
        [[p[0], p[1]], 3], // 5 метров
        { hintContent: 'Первый куст' },
        {
          fillColor: '#FFD700',
          fillOpacity: 0.8,
          strokeColor: '#FFD700',
          strokeWidth: 2,
          strokeOpacity: 1
        }
      )
      this.rowsCollection.add(startCircle)
    }
    this.rowsCollection.add(rowLine)
    return numBushes
  }

  getPolygonSide(points) {
    if (!points || points.length < 2 || this.referenceSideIndex >= points.length - 1 || this.referenceSideIndex < 0)
      return null
    return {
      p1: points[this.referenceSideIndex],
      p2: points[this.referenceSideIndex + 1],
    }
  }

  distance(p1, p2) {
    return Math.sqrt((p1[0] - p2[0])**2 + (p1[1] - p2[1])**2)
  }

  getLineLength(points) {
    let length = 0
    for (let i = 0; i < points.length - 1; i++) {
      length += this.distance(points[i], points[i + 1])
    }
    return length
  }

  calculateLineLengthKm(p1, p2) {
    return GeometryHelpers.distance(p1, p2)
  }

  lineIntersection(p1, p2, p3, p4) {
      const denominator = (p4[1] - p3[1]) * (p2[0] - p1[0]) - (p4[0] - p3[0]) * (p2[1] - p1[1])
      if (denominator === 0) return null // Прямая и отрезок параллельны
      
      const ua = ((p4[0] - p3[0]) * (p1[1] - p3[1]) - (p4[1] - p3[1]) * (p1[0] - p3[0])) / denominator
      const ub = ((p2[0] - p1[0]) * (p1[1] - p3[1]) - (p2[1] - p1[1]) * (p1[0] - p3[0])) / denominator
      
      // ub проверяем (пересечение с отрезком), ua не проверяем (прямая бесконечна)
      if (ub < 0 || ub > 1) return null
      
      return [
        p1[0] + ua * (p2[0] - p1[0]),
        p1[1] + ua * (p2[1] - p1[1])
      ]
  }

  metersToDegrees(meters) {
    // Берем широту из центра карты или из первой точки полигона
    let lat = this.map.getCenter()[0]
    
    // 1 градус широты ≈ 111320 метров (всегда)
    const metersPerDegreeLat = 111320
    
    // 1 градус долготы зависит от широты
    const metersPerDegreeLon = 111320 * Math.cos(lat * Math.PI / 180)
    
    // Для рядов используем среднее (ряды могут идти в любом направлении)
    const avgMetersPerDegree = (metersPerDegreeLat + metersPerDegreeLon) / 2
    
    return meters / avgMetersPerDegree
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