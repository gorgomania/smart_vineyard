import { Controller } from "@hotwired/stimulus"

// Загружает JSON по url и копирует его в буфер обмена. Вместо inline onclick, который блокирует CSP
export default class extends Controller {
  static values = { url: String }

  async copy() {
    const response = await fetch(this.urlValue)
    const data = await response.json()
    await navigator.clipboard.writeText(JSON.stringify(data))
    this.element.title = "Скопировано!"
  }
}
