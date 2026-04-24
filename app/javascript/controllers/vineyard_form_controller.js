// app/javascript/controllers/vineyard_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

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