import { Controller } from "@hotwired/stimulus"

// Вместо href="javascript:history.back()": такие ссылки блокирует CSP
export default class extends Controller {
  back(event) {
    event.preventDefault()
    history.back()
  }

  forward(event) {
    event.preventDefault()
    history.forward()
  }
}
