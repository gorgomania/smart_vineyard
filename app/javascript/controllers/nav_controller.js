import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["burgerMenu", "dropMenu", "overlay"]

  connect() {
    this._handleResize = () => this.handleResize()
    window.addEventListener("resize", this._handleResize)
    this.handleResize()
  }

  disconnect() {
    window.removeEventListener("resize", this._handleResize)
  }

  // Меню и бургер показывает CSS (max-[1000px]: в header), здесь только выпадающее меню
  handleResize() {
    if (window.innerWidth < 1000) {
      if (!this.dropMenuTarget.classList.contains("hidden")) this._positionOverlay()
    } else {
      this._closeMenu()
    }
  }

  toggleMenu() {
    if (this.dropMenuTarget.classList.contains("hidden")) {
      this.dropMenuTarget.classList.remove("hidden")
      this.burgerMenuTarget.setAttribute("aria-expanded", "true")
      this._positionOverlay()
      this.overlayTarget.classList.remove("hidden", "opacity-0", "invisible", "pointer-events-none")
      this.overlayTarget.classList.add("opacity-50", "visible", "pointer-events-auto")
    } else {
      this._closeMenu()
    }
  }

  closeMenu() {
    this._closeMenu()
  }

  _positionOverlay() {
    this.overlayTarget.style.top = `${this.dropMenuTarget.getBoundingClientRect().bottom}px`
  }

  _closeMenu() {
    this.dropMenuTarget.classList.add("hidden")
    this.burgerMenuTarget.setAttribute("aria-expanded", "false")
    this.overlayTarget.classList.add("hidden", "opacity-0", "invisible", "pointer-events-none")
    this.overlayTarget.classList.remove("opacity-50", "visible", "pointer-events-auto")
  }
}
