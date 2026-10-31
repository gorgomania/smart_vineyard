import { Controller } from "@hotwired/stimulus"

// Строка над содержимым проводника: если всё не влезает по ширине, по очереди
// прячем привязанный виноградник, переносим путь на строку ниже, прячем «Вперёд», прячем «Назад»
export default class extends Controller {
  static targets = ["vineyard", "path", "history"]

  connect() {
    this.fit = this.fit.bind(this)
    this.resizeObserver = new ResizeObserver(this.fit)
    this.resizeObserver.observe(this.element)
    // Кнопки «Назад/Вперёд», flash и refresh-морфинг меняют содержимое строки, не меняя её ширину
    this.mutationObserver = new MutationObserver(this.fit)
    this.observeMutations()
    this.fit()
  }

  disconnect() {
    this.resizeObserver.disconnect()
    this.mutationObserver.disconnect()
  }

  fit() {
    // Свои же переключения не должны снова запускать fit
    this.mutationObserver.disconnect()

    // Атрибут hidden, а не класс: классом «Назад/Вперёд» прячет history-nav, когда идти некуда.
    // data-wrapped переносит путь на отдельную строку (классы data-[wrapped]: в разметке)
    const hide = el => [() => el.hidden = false, () => el.hidden = true]
    const wrap = el => [() => el.removeAttribute("data-wrapped"), () => el.setAttribute("data-wrapped", "")]
    // В разметке «Назад» идёт перед «Вперёд», а прятать «Вперёд» нужно раньше
    const steps = [
      ...this.vineyardTargets.map(hide),
      ...this.pathTargets.map(wrap),
      ...this.historyTargets.reverse().map(hide)
    ]

    steps.forEach(([reset]) => reset())
    for (const [, apply] of steps) {
      if (!this.overflows()) break
      apply()
    }

    this.observeMutations()
  }

  // Работает, только пока иконки и путь не сжимаются (shrink-0 в разметке):
  // иначе нехватка места уходит в сплющенные иконки, а не в переполнение.
  // Группы слева и справа сжиматься могут, и тогда содержимое вылезает из своей группы
  // и наезжает на соседнюю, не выходя за край строки — поэтому проверяем и их
  overflows() {
    return [this.element, ...this.element.children].some(el => el.scrollWidth > el.clientWidth)
  }

  observeMutations() {
    this.mutationObserver.observe(this.element, {
      childList: true, subtree: true, attributes: true, attributeFilter: ["class", "hidden", "data-wrapped"]
    })
  }
}
