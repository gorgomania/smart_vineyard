// Классы диагнозов: id — индекс класса модели, ключ — как в MediaItem::DIAGNOSES.
// Цвета живут в палитре (--color-diag-<ключ> в tailwind/application.css), здесь их только читаем
const KEYS = { 0: "black-rot", 1: "esca", 2: "healthy", 3: "leaf-blight" }

export function diagnosisKey(classId) {
  return KEYS[classId] ?? "none"
}

export function diagnosisColor(key) {
  return getComputedStyle(document.documentElement).getPropertyValue(`--color-diag-${key}`).trim()
}
