import "@hotwired/turbo-rails"
import "controllers"

document.addEventListener("turbo:load", () => {
  document.querySelectorAll(".flash").forEach(el => {
    setTimeout(() => {
      el.style.opacity = "0"
      setTimeout(() => el.remove(), 500)
    }, 3000)
  })
})
