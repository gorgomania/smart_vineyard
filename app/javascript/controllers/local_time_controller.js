import { Controller } from "@hotwired/stimulus"

// <time datetime="..."> → дата во времени и формате браузера. Вместо inline <script>, который блокирует CSP
export default class extends Controller {
  connect() {
    this.element.textContent = new Date(this.element.getAttribute("datetime")).toLocaleString()
  }
}
