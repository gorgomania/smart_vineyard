// app/javascript/controllers/map_controller.js
// Карта виноградников на Яндекс Картах. Режимы (data-map-mode):
//   index — все виноградники пользователя полигонами (data-map-multiple-polygons);
//   show — один виноградник: линии рядов или, с data-map-heatmap-url, тепловая карта кустов (utils/heatmap_layer);
//   new / edit — редактируемый полигон, ряды пересчитываются при каждом изменении и уходят в форму
//                (vineyard_form_controller) событиями map:geometryChanged и map:statisticsUpdated
import { Controller } from "@hotwired/stimulus"
import { GeometryHelpers } from "utils/geometry_helpers"
import { HeatmapLayer } from "utils/heatmap_layer"
import { layoutRows, bushCount } from "utils/vineyard_rows"
import { parseWKT } from "utils/wkt"

const DEFAULT_CENTER = [44.5947, 33.4756]
const FIRST_ROW_COLOR = '#FFD700' // золотой: опорная сторона и первый куст

// Цвета полигонов берём из палитры сайта (@theme в tailwind/application.css)
const brandColor = (shade) => getComputedStyle(document.documentElement)
  .getPropertyValue(shade ? `--color-brand-${shade}` : "--color-brand").trim()

export default class extends Controller {

  connect() {

    this.element.innerHTML = ''

    // Получаем данные напрямую из атрибутов
    this.apiKey = this.element.dataset.mapApiKey
    this.center = this.parseCenter(this.element.dataset.mapCenter)
    this.zoom = parseInt(this.element.dataset.mapZoom) || 10
    this.mode = this.element.dataset.mapMode
    this.vineyardData = this.element.dataset.mapVineyardData ? JSON.parse(this.element.dataset.mapVineyardData) : null
    this.multiplePolygons = this.element.dataset.mapMultiplePolygons
    this.currentPolygon = null
    this.rowsCollection = null

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

    // Тепловая карта подписывается на диагнозы сразу, не дожидаясь Яндекс Карт: до отрисовки они копятся в слое
    const heatmapUrl = this.element.dataset.mapHeatmapUrl
    this.heatmap = heatmapUrl ? new HeatmapLayer(this.element, heatmapUrl) : null

    this.loadMap()
  }

  disconnect() {
    this.stopListeningToForm()
    this.heatmap?.destroy()

    if (this.map) {
      this.map.destroy()
      this.map = null
    }
  }

  parseCenter(centerStr) {
    if (!centerStr) return DEFAULT_CENTER
    try {
      return JSON.parse(centerStr)
    } catch(e) {
      return DEFAULT_CENTER
    }
  }

  loadMap() {
    // API уже загружено другой страницей
    if (window.ymaps) {
      this.initMap()
      return
    }

    const script = document.createElement('script')
    script.src = `https://api-maps.yandex.ru/2.1/?apikey=${this.apiKey}&lang=ru_RU`
    script.onload = () => this.initMap()
    script.onerror = () => console.error('Failed to load Yandex Maps API')
    document.head.appendChild(script)
  }

  initMap() {
    ymaps.ready(() => {
      // Под тепловой картой подложки нет: точки видно лучше на чистом фоне
      this.map = new ymaps.Map(this.element, {
        center: this.center,
        zoom: this.zoom,
        type: this.heatmap ? null : 'yandex#hybrid',
        controls: this.heatmap ? ['zoomControl', 'fullscreenControl'] : ['zoomControl', 'fullscreenControl', 'geolocationControl']
      }, { autoFitToViewport: 'always' })
      this.heatmap?.attach(this.map)

      if (this.mode == "new" || this.mode == "edit") {
        this.currentPolygon = this.createPolygon(true)
      }
      else if (this.mode == "show") {
        this.currentPolygon = this.createPolygon(false)
      }

      if (this.multiplePolygons) {
        this.loadMultiplePolygons()
      }

      if (this.mode != "index") {
        this.map.geoObjects.add(this.currentPolygon)
        this.rowsCollection = new ymaps.GeoObjectCollection({}, {
          strokeColor: brandColor(),
          strokeWidth: 2,
          strokeOpacity: 0.8
        })
        this.map.geoObjects.add(this.rowsCollection)

        // Полигон двигают или правят вершины (на карте или в форме) — пересчитываем ряды и отдаём координаты форме
        this.currentPolygon.geometry.events.add('change', () => {
          const coordinates = this.currentPolygon.geometry.getCoordinates()[0]
          this.updateForm(coordinates)
          this.generateRows(coordinates)
        })
        this.showPolygon()
      }

      this.listenToForm()

      // Центр и зум — ссылкам «Список виноградников» и «Создать виноградник» (map_links_controller)
      this.map.events.add('boundschange', () => this.dispatchMapUpdated())
      this.map.events.add('zoomchange', () => this.dispatchMapUpdated())
      this.dispatchMapUpdated()
    })
  }

  createPolygon(editable) {
    return new ymaps.Polygon(
      [[]],
      { hintContent: 'Виноградник' },
      {
        draggable: editable,
        editable: editable,
        fillColor: brandColor('light'),
        fillOpacity: 0.1,
        strokeColor: brandColor(),
        strokeWidth: 3,
        visible: false, // показывает showPolygon, когда координаты уже заданы
        editorDrawing: false,
      }
    )
  }

  // События от формы виноградника (vineyard_form_controller)
  listenToForm() {
    this.stopListeningToForm()

    this.boundNextSide = () => {
      if (!this.currentPolygon?.geometry) return
      this.switchSide(+1)
    }
    this.boundPrevSide = () => {
      if (!this.currentPolygon?.geometry) return
      this.switchSide(-1)
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
    this.boundPolygonUpdated = (event) => {
      this.currentPolygon?.geometry.setCoordinates(event.detail.coordinates)
    }

    document.addEventListener('vineyard:nextSide', this.boundNextSide)
    document.addEventListener('vineyard:prevSide', this.boundPrevSide)
    document.addEventListener('vineyard:firstBushChanged', this.boundFirstBush)
    document.addEventListener('vineyard:spacingChanged', this.boundSpacing)
    document.addEventListener('form:polygonUpdated', this.boundPolygonUpdated)
  }

  stopListeningToForm() {
    document.removeEventListener('vineyard:nextSide', this.boundNextSide)
    document.removeEventListener('vineyard:prevSide', this.boundPrevSide)
    document.removeEventListener('vineyard:firstBushChanged', this.boundFirstBush)
    document.removeEventListener('vineyard:spacingChanged', this.boundSpacing)
    document.removeEventListener('form:polygonUpdated', this.boundPolygonUpdated)
  }

  dispatchMapUpdated() {
    if (!this.map) return

    document.dispatchEvent(new CustomEvent('map:updated', {
      detail: { center: this.map.getCenter(), zoom: this.map.getZoom() }
    }))
  }

  updateForm(coordinates) {
    document.dispatchEvent(new CustomEvent('map:geometryChanged', {
      detail: { coordinates: coordinates }
    }))
  }

  // Нового виноградника ещё нет — квадрат в центре карты, размер по зуму
  setDefaultRectangle() {
    const size = this.getRectangleSize()
    const center = this.map.getCenter()
    this.currentPolygon.geometry.setCoordinates([[
      [center[0] + size, center[1] - size],
      [center[0] + size, center[1] + size],
      [center[0] - size, center[1] + size],
      [center[0] - size, center[1] - size],
      [center[0] + size, center[1] - size]
    ]])
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

  // Опорная сторона по кругу: сторон столько, сколько вершин без замыкающей
  switchSide(step) {
    const coordinates = this.currentPolygon.geometry.getCoordinates()[0]
    const sides = coordinates.length - 1
    this.referenceSideIndex = (this.referenceSideIndex + step + sides) % sides
    this.generateRows(coordinates)
  }

  loadMultiplePolygons() {
    try {
      const polygonsData = JSON.parse(this.multiplePolygons)

      polygonsData.forEach(data => {
        const coordinates = parseWKT(data.polygon)
        if (!coordinates || coordinates.length < 3) return

        this.map.geoObjects.add(new ymaps.Polygon(
          [coordinates],
          {
            hintContent: `${data.name}\n🍇 ${data.grape_variety || '—'}\n📊 ${data.area} га`,
            balloonContent: `
              <div style="padding: 8px;">
                <b style="color: var(--color-brand);">${data.name}</b><br/>
                🍇 ${data.grape_variety || 'Сорт не указан'}<br/>
                📊 Площадь: ${data.area} га<br/>
                📏 Количество рядов: ${data.total_rows}<br/>
                🌿 Количество кустов: ${data.total_bushes}<br/>
                <hr style="margin: 8px 0;"/>
                <a href="/vineyards/${data.id}" style="color: var(--color-brand);">Подробнее →</a>
              </div>
            `
          },
          {
            fillColor: brandColor('light'),
            fillOpacity: 0.3,
            strokeColor: brandColor(),
            strokeWidth: 2,
            cursor: 'pointer'
          }
        ))
      })

      // Центрируем карту на всех полигонах
      if (this.mode == "index" && polygonsData.length > 0) {
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

    this.currentPolygon.options.set('visible', true)

    if (this.mode === "show") {
      this.loadExistingPolygon()
      return
    }

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
      this.setDefaultRectangle()
    }
    this.currentPolygon.editor.startEditing()
  }

  loadExistingPolygon() {
    try {
      this.currentPolygon.geometry.setCoordinates([parseWKT(this.existingPolygon)])
      this.map.setBounds(this.currentPolygon.geometry.getBounds(), {
        checkZoomRange: true,  // проверить доступные зуммы
        zoomMargin: 30         // отступ от краёв в пикселях
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

  // Ряды по полигону (utils/vineyard_rows): на тепловой карте — кусты точками, иначе — линии рядов.
  // Числа рядов, кустов и площадь уходят в форму — показать до сохранения
  generateRows(polygonPoints) {
    if (!polygonPoints || polygonPoints.length < 3) return

    this.heatmap?.reset({ rowSpacing: this.rowSpacing, bushSpacing: this.bushSpacing })
    this.rowsCollection.removeAll()

    const rows = layoutRows(polygonPoints, this.referenceSideIndex, this.rowSpacing)
    const bushesPerRow = rows.map(row => this.addRow(row))
    const totalBushes = bushesPerRow.reduce((sum, count) => sum + count, 0)

    this.sendStatisticsToForm(rows.length, totalBushes, GeometryHelpers.calculateArea(polygonPoints))
    this.heatmap?.rendered()
  }

  // Ряд на карте; возвращает число кустов в нём. Кусты нумеруются от опорной вершины
  addRow({ number, p1, p2 }) {
    const bushes = bushCount(p1, p2, this.bushSpacing)
    const [start, end] = this.referenceVertexIsFirst ? [p1, p2] : [p2, p1]

    if (this.heatmap) {
      this.heatmap.addRow(number, start, end)
      return bushes
    }

    const hint = { hintContent: `Ряд ${number} · ${bushes} ${pluralizeBushes(bushes)}` }
    if (number === 1) {
      // Опорная сторона золотая, первый куст — золотой круг на опорной вершине
      this.rowsCollection.add(new ymaps.Circle(
        [[start[0], start[1]], 3],
        { hintContent: 'Первый куст' },
        { fillColor: FIRST_ROW_COLOR, fillOpacity: 0.8, strokeColor: FIRST_ROW_COLOR, strokeWidth: 2, strokeOpacity: 1 }
      ))
      this.rowsCollection.add(new ymaps.Polyline(
        [[p1[0], p1[1]], [p2[0], p2[1]]], hint,
        { strokeColor: FIRST_ROW_COLOR, strokeWidth: 4, strokeOpacity: 0.9 }
      ))
    }
    else {
      this.rowsCollection.add(new ymaps.Polyline([[p1[0], p1[1]], [p2[0], p2[1]]], hint))
    }
    return bushes
  }

  sendStatisticsToForm(rowsCount, bushesCount, areaInHectares) {
    document.dispatchEvent(new CustomEvent('map:statisticsUpdated', {
      detail: {
        rows: rowsCount,
        bushes: bushesCount,
        area: areaInHectares.toFixed(2)
      }
    }))
  }
}

function pluralizeBushes(count) {
  if (count % 10 === 1 && count % 100 !== 11) return 'куст'
  if ([2, 3, 4].includes(count % 10) && ![12, 13, 14].includes(count % 100)) return 'куста'
  return 'кустов'
}
