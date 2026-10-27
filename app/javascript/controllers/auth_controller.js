import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label", "input"]

  connect() {
    this.labelTarget.style.transition = "top 150ms, font-size 150ms"
    if (this.inputTarget.value) this._up()
  }

  focus() {
    this._up()
  }

  blur() {
    if (!this.inputTarget.value) this._down()
  }

  input() {
    if (this.inputTarget.value) {
      this._up()
    } else if (document.activeElement !== this.inputTarget) {
      this._down()
    }
  }

  _up() {
    this.labelTarget.style.top = "22px"
    this.labelTarget.style.fontSize = "13px"
  }

  _down() {
    this.labelTarget.style.top = "42px"
    this.labelTarget.style.fontSize = "16px"
  }
}
