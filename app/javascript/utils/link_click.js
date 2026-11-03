// Клик с Ctrl/⌘ (новая вкладка), Shift (новое окно), Alt (скачать) или не левой кнопкой: ссылку открывает
// браузер где-то ещё, а текущая страница остаётся. Такие клики не перехватываем — как и сам Turbo
export function opensElsewhere(event) {
  return event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey
}
