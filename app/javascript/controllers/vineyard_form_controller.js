// app/javascript/controllers/vineyard_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  static targets = ["rowSpacing", "bushSpacing", "rowSpacingValue", "bushSpacingValue", 
                    "prevSide", "nextSide", "sideInfo", "totalSides", 
                    "firstBushStart", "firstBushEnd", "referenceSideIndex", "referenceVertexIsFirst"]

  connect() {

    // Подписываемся на события от карты
    document.addEventListener('map:polygonUpdated', (event) => {
      this.updateFormFromPolygon(event.detail)
    })

    document.addEventListener('map:statisticsUpdated', (event) => {
      this.updateStatistics(event.detail)
    })

    // Настраиваем слушатели полей формы
    this.setupFormListeners()
    this.setupSpacingListeners()
    this.setupSideButtons()
    this.setupFirstBushButtons()
  }

  updateStatistics({ rows, bushes, area }) {
    // Обновляем поля в форме
    const rowsField = document.getElementById('vineyards_rows_count')
    const bushesField = document.getElementById('vineyards_bushes_count')
    const areaField = document.getElementById('vineyards_area')
    
    if (rowsField) rowsField.value = rows
    if (bushesField) bushesField.value = bushes
    if (areaField) areaField.value = area
  }
  
  // Обновление формы из полигона карты
  updateFormFromPolygon(detail) {
    let coordinates = detail.coordinates
    
    if (!coordinates || coordinates.length < 4) {
      console.warn("No valid coordinates received")
      return
    }
    
    // Заполняем поля формы (берем первые 4 точки)
    this.setFieldValue('vineyards_north_west_lat', coordinates[0][0]?.toFixed(7) || '')
    this.setFieldValue('vineyards_north_west_lng', coordinates[0][1]?.toFixed(7) || '')
    this.setFieldValue('vineyards_north_east_lat', coordinates[1][0]?.toFixed(7) || '')
    this.setFieldValue('vineyards_north_east_lng', coordinates[1][1]?.toFixed(7) || '')
    this.setFieldValue('vineyards_south_east_lat', coordinates[2][0]?.toFixed(7) || '')
    this.setFieldValue('vineyards_south_east_lng', coordinates[2][1]?.toFixed(7) || '')
    this.setFieldValue('vineyards_south_west_lat', coordinates[3][0]?.toFixed(7) || '')
    this.setFieldValue('vineyards_south_west_lng', coordinates[3][1]?.toFixed(7) || '')
    
    this.updatePolygonField()
  }
  
  updateSidesInfo({ totalSides, currentSide }) {
    const sideInfo = this.sideInfoTarget
    const totalSidesSpan = this.totalSidesTarget
    const referenceSideIndex = this.referenceSideIndexTarget
    
    if (sideInfo) {
      sideInfo.textContent = `Сторона ${currentSide + 1} из ${totalSides}`
    }
    if (totalSidesSpan) {
      totalSidesSpan.textContent = totalSides
    }
    if (referenceSideIndex) {
      referenceSideIndex.value = currentSide
    }
  }

  // Обновление карты из полей формы
  updateMapFromForm() {
    const northWestLat = parseFloat(this.getFieldValue('vineyards_north_west_lat'))
    const northWestLng = parseFloat(this.getFieldValue('vineyards_north_west_lng'))
    const northEastLat = parseFloat(this.getFieldValue('vineyards_north_east_lat'))
    const northEastLng = parseFloat(this.getFieldValue('vineyards_north_east_lng'))
    const southEastLat = parseFloat(this.getFieldValue('vineyards_south_east_lat'))
    const southEastLng = parseFloat(this.getFieldValue('vineyards_south_east_lng'))
    const southWestLat = parseFloat(this.getFieldValue('vineyards_south_west_lat'))
    const southWestLng = parseFloat(this.getFieldValue('vineyards_south_west_lng'))
    
    if (isNaN(northWestLat) || isNaN(northWestLng) ||
        isNaN(northEastLat) || isNaN(northEastLng) ||
        isNaN(southEastLat) || isNaN(southEastLng) ||
        isNaN(southWestLat) || isNaN(southWestLng)) {
      return
    }
    
    // Отправляем все 4 точки в карту
    const coordinates = [[
      [northWestLat, northWestLng],
      [northEastLat, northEastLng],
      [southEastLat, southEastLng],
      [southWestLat, southWestLng],
      [northWestLat, northWestLng]]  // замыкаем
    ]
    
    const event = new CustomEvent('form:polygonUpdated', {
      detail: { coordinates: coordinates }
    })
    document.dispatchEvent(event)
    
    this.updatePolygonField()
  }
  
  // Обновление скрытого поля с WKT полигоном
  updatePolygonField() {
    const northWestLat = this.getFieldValue('vineyards_north_west_lat')
    const northWestLng = this.getFieldValue('vineyards_north_west_lng')
    const northEastLat = this.getFieldValue('vineyards_north_east_lat')
    const northEastLng = this.getFieldValue('vineyards_north_east_lng')
    const southEastLat = this.getFieldValue('vineyards_south_east_lat')
    const southEastLng = this.getFieldValue('vineyards_south_east_lng')
    const southWestLat = this.getFieldValue('vineyards_south_west_lat')
    const southWestLng = this.getFieldValue('vineyards_south_west_lng')
    
    const polygonInput = document.getElementById('vineyard_polygon')
    if (polygonInput && northWestLat && northWestLng) {
      const wkt = `POLYGON((${northWestLat} ${northWestLng}, ${northEastLat} ${northEastLng}, ${southEastLat} ${southEastLng}, ${southWestLat} ${southWestLng}, ${northWestLat} ${northWestLng}))`
      polygonInput.value = wkt
    }
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
      startBtn.classList.add('bg-[#69377c]', 'border-[#69377c]', 'text-white', 'pointer-events-none')
      startBtn.classList.remove('bg-[#f2f2f2]', 'text-[#69377c]', 'border-[#e5e5e5]', 'hover:bg-[#e8e8e8]')
      endBtn.classList.remove('bg-[#69377c]','border-[#69377c]', 'text-white', 'pointer-events-none')
      endBtn.classList.add('bg-[#f2f2f2]', 'hover:bg-[#e8e8e8]', 'text-[#69377c]', 'border-[#e5e5e5]')
    } else {
      endBtn.classList.add('bg-[#69377c]', 'border-[#69377c]', 'text-white', 'pointer-events-none')
      endBtn.classList.remove('bg-[#f2f2f2]', 'text-[#69377c]', 'border-[#e5e5e5]', 'hover:bg-[#e8e8e8]')
      startBtn.classList.remove('bg-[#69377c]','border-[#69377c]', 'text-white', 'pointer-events-none')
      startBtn.classList.add('bg-[#f2f2f2]', 'hover:bg-[#e8e8e8]', 'text-[#69377c]', 'border-[#e5e5e5]')
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
  
  setFieldValue(id, value) {
    const field = document.getElementById(id)
    if (field) {
        field.value = value
        $(field).trigger('input')
    } 
  }
  
  getFieldValue(id) {
    const field = document.getElementById(id)
    return field ? field.value : null
  }
  
  setupFormListeners() {
    const fieldIds = [
      'vineyards_north_west_lat', 'vineyards_north_west_lng',
      'vineyards_north_east_lat', 'vineyards_north_east_lng',
      'vineyards_south_east_lat', 'vineyards_south_east_lng',
      'vineyards_south_west_lat', 'vineyards_south_west_lng'
    ]
    
    fieldIds.forEach(id => {
      const field = document.getElementById(id)
      if (field) {
        field.addEventListener('change', () => this.updateMapFromForm())
        field.addEventListener('input', () => this.updatePolygonField())
      }
    })
  }
}