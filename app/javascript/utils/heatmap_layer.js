// Тепловая карта виноградника: точка на каждый куст, цвет — диагноз его файла.
// Диагнозы { "ряд-куст" => [id файла, класс] } сверяются с сервером (url) и обновляются сообщениями
// heatmap_bush (heatmap:bush на элементе карты); легенда (heatmap_legend_controller) получает числа
// кустов по диагнозам (heatmap:counts) и прячет диагнозы с карты (heatmap:filter).
//
// Точки — не объекты Яндекс Карт, а свой тайловый слой (utils/canvas_tile_layer): метка Яндекса — несколько
// DOM-элементов с подписками на события, 41 тысяча кустов (10 га, шаги 2 × 1.2 м) рисовалась ~20 с,
// а снималась с карты (повторная раскладка) — минуты. Тайл с кустами — десятки миллисекунд.
// Подсказку и клик по кусту ищем сами по сетке-индексу (hitTest)
import { CanvasTileLayer, TILE } from "utils/canvas_tile_layer"
import { diagnosisKey, diagnosisColor } from "utils/diagnoses"
import { rowBushPoints } from "utils/vineyard_rows"

// Сетка-индекс: столько ячеек по большей стороне участка
const GRID_CELLS = 64

// Больные кусты рисуем вторым проходом, поверх здоровых и кустов без данных: иначе соседняя точка их закрывает
const onTop = (key) => key !== 'healthy' && key !== 'none'

export class HeatmapLayer {
  constructor(element, url) {
    this.url = url
    this.element = element
    this.diagnoses = {}
    this.hiddenDiagnoses = new Set()
    this.bushes = []
    this.bushById = new Map()
    this.tiles = null
    this.sprites = {}

    // Сверки могут идти одновременно (подключение, сигнал «перечитай», переподключение): у каждой свой список
    // кустов, обновлённых сообщениями, пока она в пути
    this.activeSyncs = new Set()
    this.syncSeq = 0
    this.appliedSyncSeq = 0

    this.onBush = (e) => {
      this.activeSyncs.forEach(liveBushes => liveBushes.add(e.detail.bush))
      this.updateBush(e.detail)
    }
    this.onRefresh = () => this.sync()
    this.onFilter = (e) => {
      this.hiddenDiagnoses = new Set(e.detail.hidden)
      this.scheduleRedraw()
    }
    element.addEventListener('heatmap:bush', this.onBush)
    element.addEventListener('heatmap:refresh', this.onRefresh)
    document.addEventListener('heatmap:filter', this.onFilter)
    this.watchStream()
  }

  destroy() {
    this.element.removeEventListener('heatmap:bush', this.onBush)
    this.element.removeEventListener('heatmap:refresh', this.onRefresh)
    document.removeEventListener('heatmap:filter', this.onFilter)
    cancelAnimationFrame(this.redrawFrame)
    cancelAnimationFrame(this.legendFrame)
    cancelAnimationFrame(this.hoverFrame)
    this.streamObserver?.disconnect()
    clearTimeout(this.fallback)
    this.tiles?.remove()
  }

  // Карта готова: наведение — подсказка «Ряд N Куст M», клик — файл куста
  attach(map) {
    this.map = map
    this.projection = map.options.get('projection') || ymaps.projection.wgs84Mercator

    map.events.add('mousemove', (e) => {
      this.hoverPixels = e.get('globalPixels')
      if (this.hoverFrame) return
      this.hoverFrame = requestAnimationFrame(() => {
        this.hoverFrame = null
        if (this.hoverPixels) this.hover(this.hitTest(this.hoverPixels))
      })
    })
    map.events.add('mouseleave', () => {
      this.hoverPixels = null
      this.hover(null)
    })
    map.events.add('click', (e) => {
      const bush = this.hitTest(e.get('globalPixels'))
      if (bush?.url) window.location.href = bush.url
    })
  }

  // Перед новой раскладкой рядов: кусты собираются заново, слой перерисует rendered
  reset({ rowSpacing, bushSpacing }) {
    this.rowSpacing = rowSpacing
    this.bushSpacing = bushSpacing
    this.bushes = []
    this.bushById = new Map()
  }

  // Кусты ряда по его кускам (в порядке нумерации, utils/vineyard_rows#orientSegments), номера подряд через куски.
  // Ключ "ряд-куст" — как в Vineyard#bushes_diagnoses и MediaItem#broadcast_diagnosis
  addRow(rowNumber, segments) {
    rowBushPoints(segments, this.bushSpacing).forEach(({ number, point }) => {
      const id = `${rowNumber}-${number}`
      const bush = { id, label: `Ряд ${rowNumber} Куст ${number}`, coords: [point[0], point[1]] }
      this.applyDiagnosis(bush, this.diagnoses[id])
      this.bushes.push(bush)
      this.bushById.set(id, bush)
    })
  }

  // Все ряды разложены: пиксели кустов на нулевом зуме (на зуме z — умножить на 2^z), сетка-индекс, слой
  rendered() {
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
    for (const bush of this.bushes) {
      [bush.x, bush.y] = this.projection.toGlobalPixels(bush.coords, 0)
      if (bush.x < minX) minX = bush.x
      if (bush.x > maxX) maxX = bush.x
      if (bush.y < minY) minY = bush.y
      if (bush.y > maxY) maxY = bush.y
    }
    this.buildGrid(minX, minY, maxX, maxY)
    this.latitude = this.bushes.length ? this.projection.fromGlobalPixels([(minX + maxX) / 2, (minY + maxY) / 2], 0)[0] : 0
    this.redraw()
    this.scheduleLegendUpdate()
  }

  buildGrid(minX, minY, maxX, maxY) {
    const cell = Math.max(maxX - minX, maxY - minY) / GRID_CELLS || 1
    const cols = Math.floor((maxX - minX) / cell) + 1
    const rows = Math.floor((maxY - minY) / cell) + 1
    const cells = Array.from({ length: cols * rows }, () => [])
    for (const bush of this.bushes) {
      cells[Math.floor((bush.y - minY) / cell) * cols + Math.floor((bush.x - minX) / cell)].push(bush)
    }
    this.grid = { minX, minY, cell, cols, rows, cells }
  }

  // Кусты, чьи точки попадают в прямоугольник (пиксели нулевого зума)
  bushesIn(x1, y1, x2, y2) {
    const { minX, minY, cell, cols, rows, cells } = this.grid || {}
    if (!cells) return []
    const c1 = Math.max(0, Math.floor((x1 - minX) / cell)), c2 = Math.min(cols - 1, Math.floor((x2 - minX) / cell))
    const r1 = Math.max(0, Math.floor((y1 - minY) / cell)), r2 = Math.min(rows - 1, Math.floor((y2 - minY) / cell))
    const found = []
    for (let r = r1; r <= r2; r++) {
      for (let c = c1; c <= c2; c++) {
        for (const bush of cells[r * cols + c]) {
          if (bush.x >= x1 && bush.x <= x2 && bush.y >= y1 && bush.y <= y2) found.push(bush)
        }
      }
    }
    return found
  }

  get layer() {
    return this.tiles?.layer ?? null
  }

  redraw() {
    if (!this.map) return
    this.tilesLayer().redraw()
  }

  // Картинка тайла [x, y] на зуме zoom (CanvasTileLayer#tile)
  drawTile(tile, zoom) {
    return this.tilesLayer().tile(tile, zoom)
  }

  tilesLayer() {
    return this.tiles ||= new CanvasTileLayer(this.map, (ctx, tile) => this.drawBushes(ctx, tile))
  }

  drawBushes(ctx, { left, top, zoom, ratio }) {
    const scale = 2 ** zoom
    const size = this.dotSize(zoom)
    const margin = size / 2 / scale
    const bushes = this.bushesIn(left / scale - margin, top / scale - margin,
                                 (left + TILE) / scale + margin, (top + TILE) / scale + margin)
      .filter(bush => !this.hiddenDiagnoses.has(bush.key))
    if (!bushes.length) return false

    const context = ctx()
    const offsetX = left + size / 2, offsetY = top + size / 2
    for (const upper of [false, true]) {
      for (const bush of bushes) {
        if (onTop(bush.key) !== upper) continue
        context.drawImage(this.sprite(bush.key, size, ratio),
                          Math.round((bush.x * scale - offsetX) * ratio), Math.round((bush.y * scale - offsetY) * ratio))
      }
    }
    return true
  }

  // Точка одна на диагноз и размер. Белая обводка отделяет соседние точки
  sprite(key, size, ratio) {
    const id = `${key}:${size}:${ratio}`
    if (this.sprites[id]) return this.sprites[id]

    const canvas = document.createElement('canvas')
    canvas.width = canvas.height = size * ratio
    const ctx = canvas.getContext('2d')
    const unit = size * ratio / 12 // как прежняя иконка: круг r=5.25 и обводка 1.5 в квадрате 12×12
    ctx.beginPath()
    ctx.arc(6 * unit, 6 * unit, 5.25 * unit, 0, 2 * Math.PI)
    ctx.fillStyle = diagnosisColor(key)
    ctx.fill()
    ctx.lineWidth = 1.5 * unit
    ctx.strokeStyle = 'white'
    ctx.stroke()
    return this.sprites[id] = canvas
  }

  // Размер точек по зуму: доля расстояния между кустами в пикселях, от 4 до 14px.
  // На общем плане точки не сливаются в полосы, при приближении растут
  dotSize(zoom) {
    const metersPerPixel = 156543.034 * Math.cos(this.latitude * Math.PI / 180) / 2 ** zoom
    const spacingPx = Math.min(this.rowSpacing, this.bushSpacing) / metersPerPixel
    return Math.round(Math.min(14, Math.max(4, spacingPx * 0.9)))
  }

  // Куст под курсором (глобальные пиксели текущего зума): сверху лежат больные — их и берём первыми, затем ближайший
  hitTest([px, py]) {
    if (!this.map || !this.grid) return null
    const zoom = this.map.getZoom()
    const scale = 2 ** zoom
    const radius = this.dotSize(zoom) / 2
    const x = px / scale, y = py / scale, r = radius / scale

    let best = null, bestScore = Infinity
    for (const bush of this.bushesIn(x - r, y - r, x + r, y + r)) {
      if (this.hiddenDiagnoses.has(bush.key)) continue
      const distance = Math.hypot(bush.x - x, bush.y - y) * scale
      if (distance > radius) continue
      const score = distance - (onTop(bush.key) ? 2 * radius : 0)
      if (score < bestScore) {
        best = bush
        bestScore = score
      }
    }
    return best
  }

  hover(bush) {
    if (bush === this.hovered) return
    this.hovered = bush

    this.cursor?.remove()
    this.cursor = bush?.url ? this.map.cursors.push('pointer') : null
    if (bush) this.map.hint.open(bush.coords, bush.label)
    else this.map.hint.close()
  }

  applyDiagnosis(bush, [mediaItemId, classId] = [null, null]) {
    bush.url = mediaItemId ? `/media_items/${mediaItemId}` : null
    bush.key = diagnosisKey(classId)
  }

  // Диагнозы грузим, когда подписка на heatmap_bush подключилась (атрибут connected — и после обрыва связи тоже):
  // всё, что классифицируется позже, придёт сообщением. Обычно это раньше, чем загрузятся Яндекс Карты, так что запрос один
  watchStream() {
    const stream = document.getElementById('heatmap-stream')
    if (!stream) return

    this.streamObserver = new MutationObserver(() => {
      if (stream.hasAttribute('connected')) this.sync()
    })
    this.streamObserver.observe(stream, { attributes: true, attributeFilter: ['connected'] })
    if (stream.hasAttribute('connected')) this.sync()

    // WebSocket не поднялся за секунду — грузим без подписки, чтобы карта не осталась серой; при подключении сверимся ещё раз
    this.fallback = setTimeout(() => {
      if (!this.requested) this.sync()
    }, 1000)
  }

  async sync() {
    this.requested = true
    const seq = ++this.syncSeq
    // Сообщение, пришедшее пока идёт запрос, новее ответа — ответ его не перетирает
    const liveBushes = new Set()
    this.activeSyncs.add(liveBushes)
    let diagnoses
    try {
      const response = await fetch(this.url, { headers: { Accept: 'application/json' } })
      if (!response.ok) return
      diagnoses = await response.json()
    } catch {
      return // нет сети — сверимся после переподключения
    } finally {
      this.activeSyncs.delete(liveBushes)
    }

    // Ответ более ранней сверки пришёл после более поздней — он старее уже применённого
    if (seq < this.appliedSyncSeq) return
    this.appliedSyncSeq = seq

    Object.entries(diagnoses).forEach(([bush, [mediaItemId, classId]]) => {
      if (!liveBushes.has(bush)) this.updateBush({ bush, mediaItemId, classId })
    })
    // Куста нет в ответе — файл с него открепили: снова серый
    Object.keys(this.diagnoses).forEach(bush => {
      if (!(bush in diagnoses) && !liveBushes.has(bush)) this.updateBush({ bush, mediaItemId: null, classId: null })
    })
  }

  // Пришёл результат классификации (heatmap:bush из application.js): меняем цвет куста, слой перерисуем раз за кадр
  updateBush({ bush, mediaItemId, classId }) {
    // Из сообщения id приходят строками, из JSON — числами
    const current = this.diagnoses[bush]
    if (current && String(current[0]) === String(mediaItemId) && String(current[1]) === String(classId)) return

    // Запоминаем всегда: если карта ещё грузится, addRow возьмёт цвет отсюда
    this.diagnoses[bush] = [mediaItemId, classId]

    const target = this.bushById.get(bush)
    if (!target) return

    this.applyDiagnosis(target, [mediaItemId, classId])
    this.scheduleRedraw()
    this.scheduleLegendUpdate()
  }

  // При сверке кусты обновляются сотнями подряд — слой перерисовываем раз за кадр
  scheduleRedraw() {
    if (this.redrawFrame) return

    this.redrawFrame = requestAnimationFrame(() => {
      this.redrawFrame = null
      if (this.grid) this.redraw()
    })
  }

  // Числа в легенде — тоже раз за кадр
  scheduleLegendUpdate() {
    if (this.legendFrame) return

    this.legendFrame = requestAnimationFrame(() => {
      this.legendFrame = null
      const counts = {}
      this.bushes.forEach(({ key }) => { counts[key] = (counts[key] || 0) + 1 })
      document.dispatchEvent(new CustomEvent('heatmap:counts', { detail: { counts } }))
    })
  }
}
