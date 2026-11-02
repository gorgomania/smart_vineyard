// app/javascript/controllers/vineyard_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  static targets = ["rowSpacing", "bushSpacing", "rowSpacingValue", "bushSpacingValue", 
                    "prevSide", "nextSide", "sideInfo", "totalSides", 
                    "firstBushStart", "firstBushEnd", "referenceSideIndex", "referenceVertexIsFirst"]

  connect() {
    document.addEventListener('map:geometryChanged', (event) => {
      this.updateVerticesFields(event.detail.coordinates)
    })

    document.addEventListener('map:statisticsUpdated', (event) => {
      this.updateStatistics(event.detail)
    })

    document.addEventListener('vineyard:initFormFromExistingPolygon', (event) => {
      if (!event.detail.referenceVertexIsFirst) {
        // Инвертируем текущее состояние
        this.updateFirstBushButtonState('end')
      }
      this.rowSpacingTarget.value = event.detail.rowSpacing
      this.rowSpacingValueTarget.textContent = event.detail.rowSpacing.toFixed(1)
      this.bushSpacingTarget.value = event.detail.bushSpacing
      this.bushSpacingValueTarget.textContent = event.detail.bushSpacing
    })

    // Настраиваем слушатели полей формы
    this.setupSpacingListeners()
    this.setupSideButtons()
    this.setupFirstBushButtons()
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
    
    // Отправляем обновленные вершины на карту
    const coordinates = [vertices.map(v => [v.lat, v.lng])]
    coordinates[0].push([vertices[0].lat, vertices[0].lng]) // замыкаем полигон
    
    const polygonEvent = new CustomEvent('form:polygonUpdated', {
      detail: { coordinates: coordinates }
    })
    document.dispatchEvent(polygonEvent)
  }

  collectVerticesFromForm() {
    const vertices = []
    const latInputs = document.querySelectorAll('[data-vertex-lat]')
    
    latInputs.forEach(latInput => {
      const index = latInput.dataset.vertexLat
      const lngInput = document.querySelector(`[data-vertex-lng="${index}"]`)
      if (lngInput) {
        vertices.push({
          lat: parseFloat(latInput.value),
          lng: parseFloat(lngInput.value)
        })
      }
    })
    
    return vertices
  }

  // Числа с карты — только показать: при сохранении раскладку и площадь сервер считает сам (VineyardLayout)
  updateStatistics({ rows, bushes, area }) {
    const rowsField = document.getElementById('vineyard_total_rows')
    const bushesField = document.getElementById('vineyard_total_bushes')
    const areaField = document.getElementById('vineyard_area_hectares')
    if (rowsField) rowsField.value = rows
    if (bushesField) bushesField.value = bushes
    if (areaField) areaField.value = area + " га"
  }
  
  updateSidesInfo({ direction }) {
    let referenceSideIndex = parseInt(this.referenceSideIndexTarget.value) || 0
    const vertexCount = document.querySelectorAll('.vertex-group').length
    if (direction == "next") {
      if (referenceSideIndex + 1 < vertexCount) {
        referenceSideIndex += 1
      }
      else {
        referenceSideIndex = 0
      }
    }
    else {
      if (referenceSideIndex - 1 >= 0) {
        referenceSideIndex -= 1
      }
      else {
        referenceSideIndex = vertexCount - 1
      }
    }
    this.referenceSideIndexTarget.value = referenceSideIndex
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
        this.updateSidesInfo({ direction: "prev" })
        document.dispatchEvent(new CustomEvent('vineyard:prevSide'))
      })
    }

    // Следующая сторона
    if (this.hasNextSideTarget) {
      this.nextSideTarget.addEventListener('click', () => {
        this.updateSidesInfo({ direction: "next" })
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
        document.dispatchEvent(new CustomEvent('vineyard:firstBushChanged'))
      })
    }

    // Первый куст в конце ряда
    if (this.hasFirstBushEndTarget) {
      this.firstBushEndTarget.addEventListener('click', () => {
        this.updateFirstBushButtonState('end')
        if (this.hasReferenceVertexIsFirstTarget) {
          this.referenceVertexIsFirstTarget.value = 'false'
        }
        document.dispatchEvent(new CustomEvent('vineyard:firstBushChanged'))
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