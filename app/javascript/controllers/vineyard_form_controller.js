// app/javascript/controllers/vineyard_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  static targets = ["rowSpacing", "bushSpacing", "rowSpacingValue", "bushSpacingValue", 
                    "prevSide", "nextSide", "sideInfo", "totalSides", 
                    "firstBushStart", "firstBushEnd", "referenceSideIndex", "referenceVertexIsFirst"]

  connect() {
    // Подписки на document снимаем в disconnect: иначе после каждого перехода Turbo на форму их становилось
    // бы на одну больше, и перетаскивание вершины перестраивало бы поля столько же раз
    this.onGeometryChanged = (event) => this.updateVerticesFields(event.detail.coordinates)
    this.onStatisticsUpdated = (event) => this.updateStatistics(event.detail)
    this.onInitFromExistingPolygon = (event) => {
      if (!event.detail.referenceVertexIsFirst) {
        // Инвертируем текущее состояние
        this.updateFirstBushButtonState('end')
      }
      this.rowSpacingTarget.value = event.detail.rowSpacing
      this.rowSpacingValueTarget.textContent = event.detail.rowSpacing.toFixed(1)
      this.bushSpacingTarget.value = event.detail.bushSpacing
      this.bushSpacingValueTarget.textContent = event.detail.bushSpacing
    }
    document.addEventListener('map:geometryChanged', this.onGeometryChanged)
    document.addEventListener('map:statisticsUpdated', this.onStatisticsUpdated)
    document.addEventListener('vineyard:initFormFromExistingPolygon', this.onInitFromExistingPolygon)

    // Настраиваем слушатели полей формы
    this.setupSpacingListeners()
    this.setupSideButtons()
    this.setupFirstBushButtons()
  }

  disconnect() {
    document.removeEventListener('map:geometryChanged', this.onGeometryChanged)
    document.removeEventListener('map:statisticsUpdated', this.onStatisticsUpdated)
    document.removeEventListener('vineyard:initFormFromExistingPolygon', this.onInitFromExistingPolygon)
  }

  updateVerticesFields(vertices) {
    const container = document.getElementById('vertices-container')
    if (!container) return
    
    // Очищаем контейнер
    container.innerHTML = ''
    
    // Создаем поля для каждой вершины
    vertices.slice(0, -1).forEach((vertex, index) => {
      const vertexHtml = `
        <div class="vertex-group" data-vertex-index="${index}">
          <div class="text-brand text-sm my-1">Вершина ${index + 1}</div>
          <div class="flex justify-between gap-2 -mt-6">
            <div class="field flex-1 min-w-0">
              <label class="relative text-[13px] top-[22px] left-[13px] text-muted pointer-events-none leading-4">Широта</label>
              <input type="text" name="vineyard[vertex_${index}_lat]" value="${vertex[0]}" 
                    class="auth_input w-full px-3 rounded-lg border border-line h-[64px] bg-surface outline-none hover:bg-surface-hover focus:bg-white"
                    data-vertex-lat="${index}">
            </div>
            <div class="field flex-1 min-w-0">
              <label class="relative text-[13px] top-[22px] left-[13px] text-muted pointer-events-none leading-4">Долгота</label>
              <input type="text" name="vineyard[vertex_${index}_lng]" value="${vertex[1]}" 
                    class="auth_input w-full px-3 rounded-lg border border-line h-[64px] bg-surface outline-none hover:bg-surface-hover focus:bg-white"
                    data-vertex-lng="${index}">
            </div>
          </div>
        </div>
      `
      container.insertAdjacentHTML('beforeend', vertexHtml)
    })
    
    // Добавляем обработчики для новых полей
    this.setupVertexListeners()
  }

  setupVertexListeners() {
    const latInputs = document.querySelectorAll('[data-vertex-lat]')
    const lngInputs = document.querySelectorAll('[data-vertex-lng]')
    
    latInputs.forEach(input => {
      input.addEventListener('change', this.vertexChangeHandler.bind(this))
    })
    
    lngInputs.forEach(input => {
      input.addEventListener('change', this.vertexChangeHandler.bind(this))
    })
  }

  vertexChangeHandler() {
    const vertices = this.collectVerticesFromForm()
    // Не число — карту не трогаем, поле подсвечено: иначе вершина улетела бы (parseFloat("44,59") = 44) или стала NaN
    if (!vertices) return

    // Отправляем обновленные вершины на карту
    const coordinates = [vertices.map(v => [v.lat, v.lng])]
    coordinates[0].push([vertices[0].lat, vertices[0].lng]) // замыкаем полигон
    
    const polygonEvent = new CustomEvent('form:polygonUpdated', {
      detail: { coordinates: coordinates }
    })
    document.dispatchEvent(polygonEvent)
  }

  // Вершины из полей формы или null, если хоть одно поле — не число (такие поля подсвечиваются)
  collectVerticesFromForm() {
    const vertices = []
    let valid = true
    const latInputs = document.querySelectorAll('[data-vertex-lat]')

    latInputs.forEach(latInput => {
      const index = latInput.dataset.vertexLat
      const lngInput = document.querySelector(`[data-vertex-lng="${index}"]`)
      if (!lngInput) return

      const lat = this.readCoordinate(latInput)
      const lng = this.readCoordinate(lngInput)
      if (lat === null || lng === null) valid = false
      vertices.push({ lat, lng })
    })

    return valid ? vertices : null
  }

  // Число из поля координаты: десятичная запятая (русская раскладка) — тоже точка, и в самом поле,
  // чтобы на сервер ушло то же, что на карту. Не число — null и красная рамка
  readCoordinate(input) {
    const text = input.value.trim().replace(',', '.')
    const value = /^-?\d+(\.\d+)?$/.test(text) ? Number(text) : NaN
    const valid = Number.isFinite(value)
    if (valid) input.value = text
    input.classList.toggle('!border-danger', !valid)
    input.classList.toggle('!bg-danger-bg', !valid)
    return valid ? value : null
  }

  // Числа с карты — только показать: при сохранении раскладку и площадь сервер считает сам (VineyardLayout).
  // Номер опорной стороны ведёт карта (переключает сторону, поправляет его после удаления вершины), форма его хранит
  updateStatistics({ rows, bushes, area, referenceSideIndex }) {
    const rowsField = document.getElementById('vineyard_total_rows')
    const bushesField = document.getElementById('vineyard_total_bushes')
    const areaField = document.getElementById('vineyard_area_hectares')
    if (rowsField) rowsField.value = rows
    if (bushesField) bushesField.value = bushes
    if (areaField) areaField.value = area + " га"
    if (this.hasReferenceSideIndexTarget) this.referenceSideIndexTarget.value = referenceSideIndex
  }

  setupSpacingListeners() {
    // Расстояние между рядами
    if (this.hasRowSpacingTarget && this.hasRowSpacingValueTarget) {
      this.rowSpacingTarget.addEventListener('input', (e) => {
        const value = parseFloat(e.target.value).toFixed(1)
        this.rowSpacingValueTarget.textContent = value
        this.dispatchSpacingChanged()
      })
    }

    // Расстояние между кустами
    if (this.hasBushSpacingTarget && this.hasBushSpacingValueTarget) {
      this.bushSpacingTarget.addEventListener('input', (e) => {
        const value = parseFloat(e.target.value).toFixed(1)
        this.bushSpacingValueTarget.textContent = value
        this.dispatchSpacingChanged()
      })
    }
  }

  setupSideButtons() {
    // Предыдущая сторона
    if (this.hasPrevSideTarget) {
      this.prevSideTarget.addEventListener('click', () => {
        document.dispatchEvent(new CustomEvent('vineyard:prevSide'))
      })
    }

    // Следующая сторона
    if (this.hasNextSideTarget) {
      this.nextSideTarget.addEventListener('click', () => {
        document.dispatchEvent(new CustomEvent('vineyard:nextSide'))
      })
    }
  }

  setupFirstBushButtons() {
    // Первый куст в начале ряда
    if (this.hasFirstBushStartTarget) {
      this.firstBushStartTarget.addEventListener('click', () => {
        this.updateFirstBushButtonState('start')
        if (this.hasReferenceVertexIsFirstTarget) {
          this.referenceVertexIsFirstTarget.value = 'true'
        }
        document.dispatchEvent(new CustomEvent('vineyard:firstBushChanged', { detail: { referenceVertexIsFirst: true } }))
      })
    }

    // Первый куст в конце ряда
    if (this.hasFirstBushEndTarget) {
      this.firstBushEndTarget.addEventListener('click', () => {
        this.updateFirstBushButtonState('end')
        if (this.hasReferenceVertexIsFirstTarget) {
          this.referenceVertexIsFirstTarget.value = 'false'
        }
        document.dispatchEvent(new CustomEvent('vineyard:firstBushChanged', { detail: { referenceVertexIsFirst: false } }))
      })
    }
  }

  updateFirstBushButtonState(active) {
    const startBtn = this.firstBushStartTarget
    const endBtn = this.firstBushEndTarget
    if (active === 'start') {
      startBtn.classList.add('bg-brand', 'border-brand', 'text-white', 'pointer-events-none')
      startBtn.classList.remove('bg-surface', 'text-brand', 'border-line', 'hover:bg-surface-hover')
      endBtn.classList.remove('bg-brand','border-brand', 'text-white', 'pointer-events-none')
      endBtn.classList.add('bg-surface', 'hover:bg-surface-hover', 'text-brand', 'border-line')
    } else {
      endBtn.classList.add('bg-brand', 'border-brand', 'text-white', 'pointer-events-none')
      endBtn.classList.remove('bg-surface', 'text-brand', 'border-line', 'hover:bg-surface-hover')
      startBtn.classList.remove('bg-brand','border-brand', 'text-white', 'pointer-events-none')
      startBtn.classList.add('bg-surface', 'hover:bg-surface-hover', 'text-brand', 'border-line')
    }
  }

  dispatchSpacingChanged() {
    const event = new CustomEvent('vineyard:spacingChanged', {
      detail: { 
        rowSpacing: parseFloat(this.rowSpacingTarget.value), 
        bushSpacing: parseFloat(this.bushSpacingTarget.value) 
      }
    })
    document.dispatchEvent(event)
  }
}