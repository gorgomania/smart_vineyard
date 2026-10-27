import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["desktopMenu", "burgerMenu", "dropMenu", "overlay"]

  connect() {
    this._handleResize = () => this.handleResize()
    window.addEventListener("resize", this._handleResize)
    this.handleResize()
  }

  disconnect() {
    window.removeEventListener("resize", this._handleResize)
  }

  handleResize() {
    if (window.innerWidth < 1000) {
      this.desktopMenuTarget.classList.add("hidden")
      this.burgerMenuTarget.classList.remove("hidden")
    } else {
      this.dropMenuTarget.classList.add("hidden")
      this.overlayTarget.classList.add("hidden")
      this.burgerMenuTarget.classList.add("hidden")
      this.desktopMenuTarget.classList.remove("hidden")
    }
  }

  toggleMenu() {
    if (this.dropMenuTarget.classList.contains("hidden")) {
      this.dropMenuTarget.classList.remove("hidden")
      this.overlayTarget.classList.remove("hidden", "opacity-0", "invisible", "pointer-events-none")
      this.overlayTarget.classList.add("opacity-50", "visible", "pointer-events-auto")
    } else {
      this._closeMenu()
    }
  }

  closeMenu() {
    this._closeMenu()
  }

  _closeMenu() {
    this.dropMenuTarget.classList.add("hidden")
    this.overlayTarget.classList.add("hidden", "opacity-0", "invisible", "pointer-events-none")
    this.overlayTarget.classList.remove("opacity-50", "visible", "pointer-events-auto")
  }
}
