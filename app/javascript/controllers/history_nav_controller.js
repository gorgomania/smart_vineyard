import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["back", "forward"]

  connect() {
    this._onPopState = () => this.update()
    window.addEventListener("popstate", this._onPopState)
    this.update()
  }

  disconnect() {
    window.removeEventListener("popstate", this._onPopState)
  }

  update() {
    if (!window.navigation) {
      if (this.hasBackTarget) this.backTarget.classList.add("hidden")
      if (this.hasForwardTarget) this.forwardTarget.classList.add("hidden")
      return
    }
    if (this.hasBackTarget) {
      this.backTarget.classList.toggle("hidden", !window.navigation.canGoBack)
    }
    if (this.hasForwardTarget) {
      this.forwardTarget.classList.toggle("hidden", !window.navigation.canGoForward)
    }
  }
}
