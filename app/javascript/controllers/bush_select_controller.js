// app/javascript/controllers/bush_select_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  
  async loadRows(event) {
    const vineyardId = event.target.value
    const rowsContainer = document.getElementById('rows-container')
    const bushesContainer = document.getElementById('bushes-container')
    
    if (!vineyardId) {
      rowsContainer.style.display = 'none'
      bushesContainer.style.display = 'none'
      return
    }
    
    // Загружаем ряды для выбранного виноградника
    const response = await fetch(`/vineyards/${vineyardId}/rows.json`)
    const rows = await response.json()
    
    const rowSelect = document.getElementById('row_id')
    rowSelect.innerHTML = '<option value="">- Выберите ряд -</option>'
    
    rows.forEach(row => {
      rowSelect.innerHTML += `<option value="${row.id}">Ряд ${row.row_number} (${row.bushes_count || 0} кустов)</option>`
    })
    
    rowsContainer.style.display = 'block'
    bushesContainer.style.display = 'none'
  }
  
  async loadBushes(event) {
    const rowId = event.target.value
    const bushesContainer = document.getElementById('bushes-container')
    if (!rowId) {
      bushesContainer.style.display = 'none'
      return
    }
    
    // Загружаем кусты для выбранного ряда
    const response = await fetch(`/rows/${rowId}/bushes.json`)
    const bushes = await response.json()
    
    const bushSelect = document.getElementById('bush_id')
    bushSelect.innerHTML = '<option value="">- Выберите куст -</option>'
    
    bushes.forEach(bush => {
      bushSelect.innerHTML += `<option value="${bush.id}">Куст ${bush.bush_number}</option>`
    })
    
    bushesContainer.style.display = 'block'
  }
}