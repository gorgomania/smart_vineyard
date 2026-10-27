import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  imgEnter() {
    this.inputTarget.style.background = "white"
    this.inputTarget.style.boxShadow = "0 0 0 1px #0000000a,0 4px 4px #0000000a,0 20px 40px #00000014"
  }

  imgLeave() {
    if (document.activeElement !== this.inputTarget) {
      this.inputTarget.style.background = ""
      this.inputTarget.style.boxShadow = ""
    }
  }
}
