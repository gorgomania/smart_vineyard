// Раскладка виноградника без Яндекс Карт: ряды по полигону и кусты вдоль ряда.
// Точки — [lat, lng], как в геометрии полигона на карте
import { GeometryHelpers } from "utils/geometry_helpers"

// Опорная сторона полигона: от вершины index к следующей
export function polygonSide(points, index) {
  if (!points || points.length < 2 || index >= points.length - 1 || index < 0) return null
  return { p1: points[index], p2: points[index + 1] }
}

// Метров в градусе широты — на той же сфере, что GeometryHelpers.kmDistance (R = 6371 км)
const METERS_PER_DEGREE = 6371000 * Math.PI / 180

// Первый ряд — опорная сторона, остальные параллельно ей через rowSpacing метров: сначала в одну сторону,
// потом в другую, пока линия пересекает полигон. Номер ряда — порядок обхода (так же их нумерует сервер).
// Тот же расчёт на сервере — VineyardLayout (app/services/vineyard_layout.rb): меняя один, меняйте и другой
export function layoutRows(polygonPoints, sideIndex, rowSpacing) {
  const first = polygonSide(polygonPoints, sideIndex)
  if (!first) return []

  // Перпендикуляр считаем в метрах на местной плоскости: градус долготы короче градуса широты в cos(широты) раз,
  // и перпендикуляр «в градусах» был бы и не перпендикулярен, и не той длины
  const metersPerDegreeLat = METERS_PER_DEGREE
  const metersPerDegreeLng = METERS_PER_DEGREE * Math.cos(polygonPoints[0][0] * Math.PI / 180)
  const north = (first.p2[0] - first.p1[0]) * metersPerDegreeLat
  const east = (first.p2[1] - first.p1[1]) * metersPerDegreeLng
  const length = Math.sqrt(north * north + east * east)
  // Сдвиг на один метр поперёк опорной стороны, в градусах [lat, lng]
  const perpPerMeter = [-east / length / metersPerDegreeLat, north / length / metersPerDegreeLng]

  const rows = [{ number: 1, p1: first.p1, p2: first.p2 }]
  for (const direction of [1, -1]) {
    for (let offset = direction * rowSpacing; ; offset += direction * rowSpacing) {
      const shifted = GeometryHelpers.shiftLine(first.p1, first.p2, perpPerMeter, offset)
      const intersections = GeometryHelpers.getIntersectionsWithPolygon(shifted.p1, shifted.p2, polygonPoints)
      if (intersections.length !== 2) break

      rows.push({ number: rows.length + 1, p1: intersections[0], p2: intersections[1] })
    }
  }
  return rows
}

// Кустов в ряду: первый плюс по одному на каждые bushSpacing метров
export function bushCount(p1, p2, bushSpacing) {
  return Math.floor(GeometryHelpers.kmDistance(p1, p2) * 1000 / bushSpacing) + 1
}

// Кусты вдоль ряда от start к end: { number, point }, номер с 1 от start
export function bushPoints(start, end, bushSpacing) {
  const steps = bushCount(start, end, bushSpacing) - 1
  const bushes = []
  for (let i = 0; i <= steps; i++) {
    const point = GeometryHelpers.interpolateOnLine([start, end], i / steps)
    if (point) bushes.push({ number: i + 1, point })
  }
  return bushes
}
