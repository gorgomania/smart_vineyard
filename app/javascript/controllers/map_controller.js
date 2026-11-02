// app/javascript/controllers/map_controller.js
// Карта виноградников на Яндекс Картах. Режимы (data-map-mode):
//   index — все виноградники пользователя полигонами (data-map-multiple-polygons);
//   show — один виноградник: линии рядов или, с data-map-heatmap-url, тепловая карта кустов (utils/heatmap_layer);
//   new / edit — редактируемый полигон, ряды пересчитываются при каждом изменении и уходят в форму
//                (vineyard_form_controller) событиями map:geometryChanged и map:statisticsUpdated
import { Controller } from "@hotwired/stimulus"
import { GeometryHelpers } from "utils/geometry_helpers"
import { HeatmapLayer } from "utils/heatmap_layer"
import { layoutRows, orientSegments, rowBushCount } from "utils/vineyard_rows"
import { parseWKT } from "utils/wkt"

const DEFAULT_CENTER = [44.5947, 33.4756]
const FIRST_ROW_COLOR = '#FFD700' // золотой: опорная сторона и первый куст

// API Яндекс Карт грузим один раз на все страницы: вторая карта, открытая, пока скрипт ещё грузится,
// не добавляет его повторно, а ждёт того же обещания
let ymapsLoading = null
function loadYmaps(apiKey) {
  if (window.ymaps) return Promise.resolve()

  ymapsLoading ||= new Promise((resolve, reject) => {
    const script = document.createElement('script')
    script.src = `https://api-maps.yandex.ru/2.1/?apikey=${apiKey}&lang=ru_RU`
    script.onload = resolve
    script.onerror = () => { ymapsLoading = null; reject(new Error('Failed to load Yandex Maps API')) }
    document.head.appendChild(script)
  })
  return ymapsLoading
}

// Название и сорт — текст пользователя, а подсказки Яндекс Карт показывают HTML
const escapeHtml = (text) => String(text ?? '').replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`)

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
    // Ушли со страницы раньше, чем загрузились Яндекс Карты: initMap по этому признаку ничего не создаст
    this.loadToken = null
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
    const token = this.loadToken = {}
    loadYmaps(this.apiKey)
      .then(() => this.initMap(token))
      .catch((error) => console.error(error.message))
  }

  // token — от этого подключения: если контроллер уже отключили (или подключили заново), карту не создаём,
  // иначе она легла бы на отключённый элемент, а подписки на события формы остались бы висеть
  initMap(token) {
    ymaps.ready(() => {
      if (this.loadToken !== token) return

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
    // Форма присылает выбранное значение, а не «переключи»: повторное нажатие уже выбранной кнопки
    // (с клавиатуры её pointer-events-none не останавливает) иначе перевернуло бы нумерацию
    this.boundFirstBush = (event) => {
      if (!this.currentPolygon?.geometry) return
      this.referenceVertexIsFirst = event.detail.referenceVertexIsFirst
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
            hintContent: `${escapeHtml(data.name)}\n🍇 ${escapeHtml(data.grape_variety || '—')}\n📊 ${data.area} га`,
            balloonContent: `
              <div style="padding: 8px;">
                <b style="color: var(--color-brand);">${escapeHtml(data.name)}</b><br/>
                🍇 ${escapeHtml(data.grape_variety || 'Сорт не указан')}<br/>
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

    // Вершину удалили в редакторе — опорной стороны с таким номером больше нет: берём последнюю,
    // иначе рядов не было бы вовсе (форма получит исправленный номер в map:statisticsUpdated)
    this.referenceSideIndex = Math.min(this.referenceSideIndex, polygonPoints.length - 2)

    this.heatmap?.reset({ rowSpacing: this.rowSpacing, bushSpacing: this.bushSpacing })
    this.rowsCollection.removeAll()

    const rows = layoutRows(polygonPoints, this.referenceSideIndex, this.rowSpacing)
    const bushesPerRow = rows.map(row => this.addRow(row))
    const totalBushes = bushesPerRow.reduce((sum, count) => sum + count, 0)

    this.sendStatisticsToForm(rows.length, totalBushes, GeometryHelpers.calculateArea(polygonPoints))
    this.heatmap?.rendered()
  }

  // Ряд на карте — линия на каждый его кусок (выемка участка разрывает ряд); возвращает число кустов в ряду.
  // Кусты нумеруются от опорной вершины подряд через все куски
  addRow({ number, segments }) {
    const bushes = rowBushCount(segments, this.bushSpacing)
    const oriented = orientSegments(segments, this.referenceVertexIsFirst)

    if (this.heatmap) {
      this.heatmap.addRow(number, oriented)
      return bushes
    }

    const hint = { hintContent: `Ряд ${number} · ${bushes} ${pluralizeBushes(bushes)}` }
    if (number === 1) {
      // Опорная сторона золотая, первый куст — золотой круг на опорной вершине
      const [start] = oriented[0]
      this.rowsCollection.add(new ymaps.Circle(
        [[start[0], start[1]], 3],
        { hintContent: 'Первый куст' },
        { fillColor: FIRST_ROW_COLOR, fillOpacity: 0.8, strokeColor: FIRST_ROW_COLOR, strokeWidth: 2, strokeOpacity: 1 }
      ))
    }
    const style = number === 1 ? { strokeColor: FIRST_ROW_COLOR, strokeWidth: 4, strokeOpacity: 0.9 } : {}
    segments.forEach(([p1, p2]) => {
      this.rowsCollection.add(new ymaps.Polyline([[p1[0], p1[1]], [p2[0], p2[1]]], hint, style))
    })
    return bushes
  }

  // Числа для показа и опорная сторона: карта — единственный её источник, форма лишь сохраняет номер
  sendStatisticsToForm(rowsCount, bushesCount, areaInHectares) {
    document.dispatchEvent(new CustomEvent('map:statisticsUpdated', {
      detail: {
        rows: rowsCount,
        bushes: bushesCount,
        area: areaInHectares.toFixed(2),
        referenceSideIndex: this.referenceSideIndex
      }
    }))
  }
}

function pluralizeBushes(count) {
  if (count % 10 === 1 && count % 100 !== 11) return 'куст'
  if ([2, 3, 4].includes(count % 10) && ![12, 13, 14].includes(count % 100)) return 'куста'
  return 'кустов'
}
