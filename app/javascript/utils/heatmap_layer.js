// Тепловая карта виноградника: точка на каждый куст, цвет — диагноз его файла.
// Диагнозы { "ряд-куст" => [id файла, класс] } сверяются с сервером (url) и обновляются сообщениями
// heatmap_bush (heatmap:bush на элементе карты); легенда (heatmap_legend_controller) получает числа
// кустов по диагнозам (heatmap:counts) и прячет диагнозы с карты (heatmap:filter)
import { diagnosisKey, diagnosisColor } from "utils/diagnoses"
import { rowBushPoints } from "utils/vineyard_rows"

export class HeatmapLayer {
  constructor(element, url) {
    this.url = url
    this.element = element
    this.diagnoses = {}
    this.hiddenDiagnoses = new Set()
    this.objectManager = null

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
      this.applyFilter()
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
    cancelAnimationFrame(this.legendFrame)
    this.streamObserver?.disconnect()
    clearTimeout(this.fallback)
  }

  // Карта готова: при смене зума точки меняют размер
  attach(map) {
    this.map = map
    map.events.add('boundschange', (e) => {
      if (e.get('newZoom') !== e.get('oldZoom')) this.resize()
    })
  }

  // Перед новой раскладкой рядов: точки рисуются заново в новый ObjectManager
  reset({ rowSpacing, bushSpacing }) {
    this.rowSpacing = rowSpacing
    this.bushSpacing = bushSpacing
    if (this.objectManager) this.map.geoObjects.remove(this.objectManager)

    this.objectManager = new ymaps.ObjectManager({ clusterize: false })
    this.map.geoObjects.add(this.objectManager)
    this.resize()

    this.objectManager.objects.events.add('click', (e) => {
      const url = this.objectManager.objects.getById(e.get('objectId')).properties.bushUrl
      if (url) window.location.href = url
    })
  }

  // Кусты ряда по его кускам (в порядке нумерации, utils/vineyard_rows#orientSegments), номера подряд через куски.
  // Ключ "ряд-куст" — как в Vineyard#bushes_diagnoses и MediaItem#broadcast_diagnosis
  addRow(rowNumber, segments) {
    rowBushPoints(segments, this.bushSpacing).forEach(({ number, point }) => {
      const id = `${rowNumber}-${number}`
      const [mediaItemId, classId] = this.diagnoses[id] || [null, null]

      this.objectManager.add({
        type: "FeatureCollection",
        features: [{
          type: "Feature",
          id,
          geometry: { type: "Point", coordinates: [point[0], point[1]] },
          properties: {
            hintContent: `Ряд ${rowNumber} Куст ${number}`,
            bushUrl: mediaItemId ? `/media_items/${mediaItemId}` : null,
            diagnosis: diagnosisKey(classId)
          },
          options: this.iconOptions(classId)
        }]
      })
    })
  }

  // Все ряды добавлены: обновить легенду и фильтр
  rendered() {
    this.scheduleLegendUpdate()
  }

  // Цвет и слой точки по диагнозу. Размер общий для всех точек, его задаёт resize
  iconOptions(classId) {
    const key = diagnosisKey(classId)

    return {
      iconLayout: 'default#image',
      // Белая обводка отделяет соседние точки и держит цвет на спутниковой подложке
      iconImageHref: 'data:image/svg+xml,' + encodeURIComponent(`
        <svg width="12" height="12" viewBox="0 0 12 12" xmlns="http://www.w3.org/2000/svg">
          <circle cx="6" cy="6" r="5.25" fill="${diagnosisColor(key)}" stroke="white" stroke-width="1.5"/>
        </svg>
      `),
      // Больные кусты поверх здоровых и кустов без данных: иначе соседняя точка их закрывает
      zIndex: key === 'healthy' || key === 'none' ? 100 : 200
    }
  }

  // Размер точек по зуму: доля расстояния между кустами в пикселях, от 4 до 14px.
  // На общем плане точки не сливаются в полосы, при приближении растут
  resize() {
    if (!this.objectManager) return

    const lat = this.map.getCenter()[0]
    const metersPerPixel = 156543.034 * Math.cos(lat * Math.PI / 180) / 2 ** this.map.getZoom()
    const spacingPx = Math.min(this.rowSpacing, this.bushSpacing) / metersPerPixel
    const size = Math.round(Math.min(14, Math.max(4, spacingPx * 0.9)))

    this.objectManager.objects.options.set({ iconImageSize: [size, size], iconImageOffset: [-size / 2, -size / 2] })
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

  // Пришёл результат классификации (heatmap:bush из application.js): перекрашиваем одну точку, карту не перерисовываем
  updateBush({ bush, mediaItemId, classId }) {
    // Из сообщения id приходят строками, из JSON — числами
    const current = this.diagnoses[bush]
    if (current && String(current[0]) === String(mediaItemId) && String(current[1]) === String(classId)) return

    // Запоминаем всегда: если карта ещё грузится, addRow возьмёт цвет отсюда
    this.diagnoses[bush] = [mediaItemId, classId]

    const obj = this.objectManager?.objects.getById(bush)
    if (!obj) return

    obj.properties.bushUrl = mediaItemId ? `/media_items/${mediaItemId}` : null
    obj.properties.diagnosis = diagnosisKey(classId)
    this.objectManager.objects.setObjectOptions(bush, this.iconOptions(classId))
    this.scheduleLegendUpdate()
  }

  // Числа в легенде и фильтр пересчитываем раз за кадр: при сверке кусты обновляются сотнями подряд
  scheduleLegendUpdate() {
    if (this.legendFrame) return

    this.legendFrame = requestAnimationFrame(() => {
      this.legendFrame = null
      if (!this.objectManager) return

      this.applyFilter()
      const counts = {}
      this.objectManager.objects.getAll().forEach(({ properties: { diagnosis } }) => {
        counts[diagnosis] = (counts[diagnosis] || 0) + 1
      })
      document.dispatchEvent(new CustomEvent('heatmap:counts', { detail: { counts } }))
    })
  }

  applyFilter() {
    this.objectManager?.setFilter(obj => !this.hiddenDiagnoses.has(obj.properties.diagnosis))
  }
}
