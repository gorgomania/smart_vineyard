import { Controller } from "@hotwired/stimulus"

// Строка над содержимым проводника: если всё не влезает по ширине,
// прячем по очереди привязанный виноградник, путь, кнопку «Вперёд», кнопку «Назад»
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
    // Свои же переключения hidden не должны снова запускать fit
    this.mutationObserver.disconnect()

    // Атрибут hidden, а не класс: классом «Назад/Вперёд» прячет history-nav, когда идти некуда
    // в порядке скрытия; в разметке «Назад» идёт перед «Вперёд», а прятать «Вперёд» нужно раньше
    const hideable = [...this.vineyardTargets, ...this.pathTargets, ...this.historyTargets.reverse()]
    hideable.forEach(el => el.hidden = false)
    for (const el of hideable) {
      if (!this.overflows()) break
      el.hidden = true
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
    this.mutationObserver.observe(this.element, { childList: true, subtree: true, attributes: true, attributeFilter: ["class", "hidden"] })
  }
}
