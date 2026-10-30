// app/javascript/controllers/bush_select_controller.js
import { Controller } from "@hotwired/stimulus"

// Показывает только свободные кусты. keepBushId — текущий куст файла при перекреплении: его тоже можно выбрать
export default class extends Controller {
  static values = { keepBushId: Number }

  async loadRows(event) {
    const vineyardId = event.target.value
    const rowsContainer = document.getElementById('rows-container')
    const bushesContainer = document.getElementById('bushes-container')

    if (!vineyardId) {
      rowsContainer.style.display = 'none'
      bushesContainer.style.display = 'none'
      return
    }

    // Загружаем ряды, в которых есть свободные кусты
    const response = await fetch(`/vineyards/${vineyardId}/rows.json${this.keepQuery}`)
    const rows = await response.json()

    const rowSelect = document.getElementById('row_id')
    rowSelect.replaceChildren(new Option(rows.length ? '- Выберите ряд -' : '- Нет свободных кустов -', ''))
    rows.forEach(row => rowSelect.add(new Option(row.label, row.id)))

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

    // Загружаем свободные кусты выбранного ряда
    const response = await fetch(`/rows/${rowId}/bushes.json${this.keepQuery}`)
    const bushes = await response.json()

    const bushSelect = document.getElementById('bush_id')
    bushSelect.replaceChildren(new Option('- Выберите куст -', ''))
    bushes.forEach(bush => bushSelect.add(new Option(`Куст ${bush.bush_number}`, bush.id)))

    bushesContainer.style.display = 'block'
  }

  get keepQuery() {
    return this.hasKeepBushIdValue ? `?keep_bush_id=${this.keepBushIdValue}` : ''
  }
}
