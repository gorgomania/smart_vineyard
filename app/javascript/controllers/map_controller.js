// app/javascript/controllers/map_controller.js
import { Controller } from "@hotwired/stimulus"
import { GeometryHelpers } from "utils/geometry_helpers"

export default class extends Controller {

  connect() {
    // Получаем данные напрямую из атрибутов
    this.apiKey = this.element.dataset.mapApiKey
    this.center = this.parseCenter(this.element.dataset.mapCenter)
    this.zoom = parseInt(this.element.dataset.mapZoom) || 10
    this.mode = this.element.dataset.mapMode
    this.vineyardData = this.element.dataset.mapVineyardData ? JSON.parse(this.element.dataset.mapVineyardData) : null
    this.multiplePolygons = this.element.dataset.mapMultiplePolygons
    this.bushesVision = this.element.dataset.mapBushesVision ? JSON.parse(this.element.dataset.mapBushesVision) : null
    this.currentPolygon = null
    this.rowsCollection = null
    this.objectManager = null

    // Устанавливаем параметры из данных виноградника или значения по умолчанию
    if (this.vineyardData) {
      this.rowSpacing = this.vineyardData.row_spacing
      this.bushSpacing = this.vineyardData.bush_spacing
      this.referenceSideIndex = this.vineyardData.reference_side_index
      this.referenceVertexIsFirst = this.vineyardData.reference_vertex_is_first
      this.existingPolygon = this.vineyardData.polygon
    } else {
      this.rowSpacing = 3.0
      this.bushSpacing = 1.5
      this.referenceSideIndex = 0
      this.referenceVertexIsFirst = true
      this.existingPolygon = null
    }

    if (!this.apiKey) {
      console.error('Map API key is missing')
      return
    }
    
    this.loadMap()
  }

  disconnect() {
    // Очищаем обработчики при уничтожении контроллера
    document.removeEventListener('vineyard:nextSide', this.boundNextSide)
    document.removeEventListener('vineyard:prevSide', this.boundPrevSide)
    document.removeEventListener('vineyard:firstBushChanged', this.boundFirstBush)
    document.removeEventListener('vineyard:spacingChanged', this.boundSpacing)
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
      if (!this.bushesVision) {
        this.map = new ymaps.Map(this.element, {
          center: this.center,
          zoom: this.zoom,
          type: 'yandex#hybrid',
          controls: ['zoomControl', 'fullscreenControl', 'geolocationControl']
        })
      }
      else {
        this.map = new ymaps.Map(this.element, {
          center: this.center,
          zoom: this.zoom,
          type: null, 
          controls: ['zoomControl', 'fullscreenControl'] 
        });
      }
      

      this.element.__mapInstance = this.map

      if (this.mode == "new" || this.mode == "edit") {
        // Создаем объект прямоугольника
        this.currentPolygon = new ymaps.Polygon(
          [[]],
          {
            hintContent: 'Виноградник'
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
      }
      else if (this.mode == "show") {
        // Создаем объект прямоугольника
        this.currentPolygon = new ymaps.Polygon(
          [[]],
          {
            hintContent: 'Виноградник',
            balloonContent: 'Перетащите углы для изменения размера'
          },
          {
            draggable: false,      // Можно перетаскивать
            editable: false,       // Включает режим редактирования
            fillColor: '#8a579f',
            fillOpacity: 0.1,
            strokeColor: '#69377c',
            strokeWidth: 3,
            visible: false,             // Сначала скрыт
            editorDrawing: false,      
          }
        )
        if (this.bushesVision) {
          this.objectManager = new ymaps.ObjectManager({
            clusterize: false
          });

          this.objectManager.objects.options.set({
            iconLayout: 'default#image',
            iconImageHref: 'data:image/svg+xml,' + encodeURIComponent(`
              <svg width="4" height="4" xmlns="http://www.w3.org/2000/svg">
                <circle cx="2" cy="2" r="2" fill="#2ECC40"/>
              </svg>
            `),
            iconImageSize: [4, 4],
            iconImageOffset: [-2, -2]
          })

          this.map.geoObjects.add(this.objectManager)
        }
      }
      else {
        this.loadMultiplePolygons()
      }

      if (this.mode != "index") {
        // Добавляем прямоугольник на карту
        this.map.geoObjects.add(this.currentPolygon)
        // Создаем коллекции для рядов и кустов
        this.rowsCollection = new ymaps.GeoObjectCollection({}, {
          strokeColor: '#69377c',
          strokeWidth: 2,
          strokeOpacity: 0.8
        })
      
        this.map.geoObjects.add(this.rowsCollection)
        // Слушаем изменения геометрии
        this.currentPolygon.geometry.events.add('change', () => {
          const coordinates = this.currentPolygon.geometry.getCoordinates()[0]
          this.updateForm(coordinates)
          this.generateRows(coordinates)
        })
        this.showPolygon()
      }

      if (this.boundNextSide) {
        document.removeEventListener('vineyard:nextSide', this.boundNextSide)
        document.removeEventListener('vineyard:prevSide', this.boundPrevSide)
        document.removeEventListener('vineyard:firstBushChanged', this.boundFirstBush)
        document.removeEventListener('vineyard:spacingChanged', this.boundSpacing)
      }
      
      // Создаем новые привязанные функции
      this.boundNextSide = () => {
        if (!this.currentPolygon?.geometry) return
        this.switchToNextSide()
      }
      
      this.boundPrevSide = () => {
        if (!this.currentPolygon?.geometry) return
        this.switchToPreviousSide()
      }
      
      this.boundFirstBush = () => {
        if (!this.currentPolygon?.geometry) return
        this.referenceVertexIsFirst = !this.referenceVertexIsFirst
        this.regenerateRows()
      }
      
      this.boundSpacing = (event) => {
        if (!this.currentPolygon?.geometry) return
        this.rowSpacing = event.detail.rowSpacing
        this.bushSpacing = event.detail.bushSpacing
        this.regenerateRows()
      }

      // Добавляем обработчики
      document.addEventListener('vineyard:nextSide', this.boundNextSide)
      document.addEventListener('vineyard:prevSide', this.boundPrevSide)
      document.addEventListener('vineyard:firstBushChanged', this.boundFirstBush)
      document.addEventListener('vineyard:spacingChanged', this.boundSpacing)

      // Подписываемся на события от формы
      document.addEventListener('form:polygonUpdated', (event) => {
        if (this.currentPolygon) {
          this.currentPolygon.geometry.setCoordinates(event.detail.coordinates)
        }
      })

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

  dispatchMapUpdated() {
    if (!this.map) return
    
    const center = this.map.getCenter()
    const zoom = this.map.getZoom()
    
    const event = new CustomEvent('map:updated', {
      detail: { center, zoom }
    })
    document.dispatchEvent(event)
  }

  updateForm(coordinates) {
    const event = new CustomEvent('map:geometryChanged', {
      detail: { coordinates: coordinates }
    })
    document.dispatchEvent(event)
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

  loadMultiplePolygons() {
    try {
      const polygonsData = JSON.parse(this.multiplePolygons)
      
      polygonsData.forEach(data => {
        const coordinates = this.parseWKT(data.polygon)
        
        if (coordinates && coordinates.length >= 3) {
          const polygon = new ymaps.Polygon(
            [coordinates],
            {
              hintContent: `${data.name}\n🍇 ${data.grape_variety || '—'}\n📊 ${data.area} га`,
              balloonContent: `
                <div style="padding: 8px;">
                  <b style="color: #69377c;">${data.name}</b><br/>
                  🍇 ${data.grape_variety || 'Сорт не указан'}<br/>
                  📊 Площадь: ${data.area} га<br/>
                  📏 Количество рядов: ${data.total_rows}<br/>
                  🌿 Количество кустов: ${data.total_bushes}<br/>
                  <hr style="margin: 8px 0;"/>
                  <a href="/vineyards/${data.id}" style="color: #69377c;">Подробнее →</a>
                </div>
              `
            },
            {
              fillColor: '#8a579f',
              fillOpacity: 0.3,
              strokeColor: '#69377c',
              strokeWidth: 2,
              cursor: 'pointer'
            }
          )
          
          this.map.geoObjects.add(polygon)
        }
      })
      
      // Центрируем карту на всех полигонах
      if (polygonsData.length > 0) {
        this.map.setBounds(this.map.geoObjects.getBounds(), {
          checkZoomRange: true,
          zoomMargin: 50
        })
      }
    } catch (error) {
      console.error('Error loading multiple polygons:', error)
    }
  }

  showPolygon() {
    
    if (!this.currentPolygon) {
      console.error("Polygon not found")
      return
    }
    
    // Показываем прямоугольник
    this.currentPolygon.options.set('visible', true)

    if (this.mode === "show") {
      this.loadExistingPolygon()
    }
    else {
      if (this.vineyardData) {
        this.loadExistingPolygon()
        document.dispatchEvent(new CustomEvent('vineyard:initFormFromExistingPolygon', {
          detail: {
            rowSpacing: this.rowSpacing,
            bushSpacing: this.bushSpacing,
            referenceVertexIsFirst: this.referenceVertexIsFirst
          }
        }))
      }
      else {
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
      }
      this.currentPolygon.editor.startEditing()
    }
  }

  loadExistingPolygon() {
    try {
      // Парсим JSON строку полигона
      const polygonData = this.existingPolygon
      // Извлекаем координаты из WKT или GeoJSON
      let coordinates
      
      coordinates = this.parseWKT(polygonData)
      this.currentPolygon.geometry.setCoordinates([coordinates])
      const bounds = this.currentPolygon.geometry.getBounds()
      this.map.setBounds(bounds, {
        checkZoomRange: true,  // проверить доступные зуммы
        zoomMargin: 30          // отступ от краёв в пикселях
      })
    } catch (error) {
      console.error('Error loading existing polygon:', error)
    }
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
    const bushesPerRow = []
    // 1. Находим самую длинную сторону (первый ряд)
    const firstRow = this.getPolygonSide(polygonPoints)

    // 2. Добавляем первый ряд
    let totalBushes = this.addRow(firstRow.p1, firstRow.p2, 1, true)
    bushesPerRow.push(totalBushes)
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
      const shiftedRow = GeometryHelpers.shiftLine(firstRow.p1, firstRow.p2, perpUnit, offset)
      const intersections = GeometryHelpers.getIntersectionsWithPolygon(shiftedRow.p1, shiftedRow.p2, polygonPoints)
      if (intersections.length === 2) {
        numRows += 1
        const numBushes = this.addRow(intersections[0], intersections[1], numRows, false, totalBushes)
        bushesPerRow.push(numBushes)
        totalBushes += numBushes
        offset += stepDeg
      } else {
        hasNextRow = false
      }
    }
    // В другую сторону
    offset = -stepDeg
    hasNextRow = true
    while (hasNextRow) {
      const shiftedRow = GeometryHelpers.shiftLine(firstRow.p1, firstRow.p2, perpUnit, offset)
      const intersections = GeometryHelpers.getIntersectionsWithPolygon(shiftedRow.p1, shiftedRow.p2, polygonPoints)
      if (intersections.length === 2) {
        numRows += 1
        const numBushes = this.addRow(intersections[0], intersections[1], numRows, false, totalBushes)
        bushesPerRow.push(numBushes)
        totalBushes += numBushes
        offset -= stepDeg
      } else {
        hasNextRow = false
      }
    }
    
    const areaInHectares = GeometryHelpers.calculateArea(polygonPoints)
    this.sendStatisticsToForm(numRows, totalBushes, areaInHectares, bushesPerRow)
  }

  // Добавление ряда
  addRow(p1, p2, rowNumber, isFirstRow = false, bushesStartIndex = 0) {
    // Вычисляем количество кустов
    const rowLengthMeters = GeometryHelpers.kmDistance(p1, p2) * 1000
    const numBushes = Math.floor(rowLengthMeters / this.bushSpacing)
    //Вид рядов
    if (!this.bushesVision) {
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
    }
    //Вид кустов
    else {
      if (this.referenceVertexIsFirst) {
        this.generateBushesOnRow([p1, p2], rowNumber, bushesStartIndex)
      }
      else {
        this.generateBushesOnRow([p2, p1], rowNumber, bushesStartIndex)
      }
    }
    return numBushes
  }

  generateBushesOnRow(linePoints, rowIndex, bushesStartIndex = 0) {
    if (linePoints.length < 2) return
    
    // Длина ряда в метрах
    const rowLengthMeters = GeometryHelpers.kmDistance(linePoints[0], linePoints[linePoints.length-1]) * 1000
    
    // Количество кустов
    const numBushes = Math.floor(rowLengthMeters / this.bushSpacing)
    
    for (let i = 0; i <= numBushes; i++) {
      const t = i / numBushes // Пропорция вдоль ряда
      
      // Интерполяция позиции куста
      const bushPoint = GeometryHelpers.interpolateOnLine(linePoints, t)
      
      if (bushPoint) {
        // Добавляем куст
        const bushGeoJsonData = {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "id": bushesStartIndex + i + rowIndex,
              "geometry": {
                "type": "Point",
                "coordinates": [bushPoint[0], bushPoint[1]]
              },
              "properties": {
                "hintContent": `Ряд ${rowIndex}, Куст ${i + 1}`
              }
            }
          ]
        }
        this.objectManager.add(bushGeoJsonData)
      }
    }
  }

  getPolygonSide(points) {
    if (!points || points.length < 2 || this.referenceSideIndex >= points.length - 1 || this.referenceSideIndex < 0)
      return null
    return {
      p1: points[this.referenceSideIndex],
      p2: points[this.referenceSideIndex + 1],
    }
  }

  parseWKT(wkt) {
    // Поддержка обоих форматов: "POLYGON((...))" и "POLYGON ((...))"
    const match = wkt.match(/POLYGON\s*\(\((.+)\)\)/i)
    if (!match) {
      console.error('Invalid WKT format:', wkt)
      return null
    }
    const points = match[1].split(', ')
    const coordinates = points.map(point => {
      const [lng, lat] = point.split(' ')
      return [parseFloat(lat), parseFloat(lng)]
    })
    
    return coordinates
  }

  metersToDegrees(meters) {
    // Берем широту из центра карты
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

  sendStatisticsToForm(rowsCount, bushesCount, areaInHectares, bushesPerRow) {
  // Отправляем событие с данными о рядах и кустах
    const event = new CustomEvent('map:statisticsUpdated', {
      detail: { 
        rows: rowsCount,
        bushes: bushesCount,
        area: areaInHectares.toFixed(2),
        bushesPerRow: bushesPerRow
      }
    })
    document.dispatchEvent(event)
  }
}