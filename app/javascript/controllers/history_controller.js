import { Controller } from "@hotwired/stimulus"
import { opensElsewhere } from "utils/link_click"

// Вместо href="javascript:history.back()": такие ссылки блокирует CSP
export default class extends Controller {
  // Назад по истории, если в этой вкладке до нас была страница сайта. Если страницу открыли
  // по ссылке или в новой вкладке, возвращаться некуда — тогда идём по href ссылки (разумное место рядом)
  back(event) {
    if (opensElsewhere(event)) return // Ctrl+клик — по href в новой вкладке, а не назад в этой
    if (!this.canGoBack && this.element.getAttribute("href") !== "#") return

    event.preventDefault()
    history.back()
  }

  forward(event) {
    event.preventDefault()
    history.forward()
  }

  // Turbo нумерует записи своих переходов (restorationIndex, у первой страницы вкладки 0);
  // полную загрузку с другой страницы сайта в этой же вкладке видно по referrer и длине истории
  get canGoBack() {
    if ((history.state?.turbo?.restorationIndex || 0) > 0) return true
    return history.length > 1 && document.referrer.startsWith(location.origin)
  }
}
