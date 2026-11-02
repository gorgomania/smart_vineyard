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
// Две точки пересечения ближе этого — одна и та же (линия прошла через вершину и задела обе её стороны)
const SAME_POINT_DEGREES = 1e-12

// Ряд — линия параллельно опорной стороне: { number, segments: [[start, end], ...] }. Кусков несколько, когда линию
// разрывает выемка участка (буквы «Г», «П»): это всё равно один ряд, кусты нумеруются подряд через все куски.
// Первый ряд — опорная сторона, остальные через rowSpacing метров: сначала в одну сторону, потом в другую,
// пока линия задевает участок. Номер ряда — порядок обхода (так же их нумерует сервер).
// Тот же расчёт на сервере — VineyardLayout (app/services/vineyard_layout.rb): меняя один, меняйте и другой
export function layoutRows(polygonPoints, sideIndex, rowSpacing) {
  const first = polygonSide(polygonPoints, sideIndex)
  // Шаг не больше нуля — сдвиг не растёт, цикл ниже бесконечен
  if (!first || !(rowSpacing > 0)) return []

  // Перпендикуляр считаем в метрах на местной плоскости: градус долготы короче градуса широты в cos(широты) раз,
  // и перпендикуляр «в градусах» был бы и не перпендикулярен, и не той длины
  const metersPerDegreeLat = METERS_PER_DEGREE
  const metersPerDegreeLng = METERS_PER_DEGREE * Math.cos(polygonPoints[0][0] * Math.PI / 180)
  const north = (first.p2[0] - first.p1[0]) * metersPerDegreeLat
  const east = (first.p2[1] - first.p1[1]) * metersPerDegreeLng
  const length = Math.sqrt(north * north + east * east)
  // Сдвиг на один метр поперёк опорной стороны, в градусах [lat, lng]
  const perpPerMeter = [-east / length / metersPerDegreeLat, north / length / metersPerDegreeLng]

  const rows = [{ number: 1, segments: [[first.p1, first.p2]] }]
  for (const direction of [1, -1]) {
    for (let offset = direction * rowSpacing; ; offset += direction * rowSpacing) {
      const shifted = GeometryHelpers.shiftLine(first.p1, first.p2, perpPerMeter, offset)
      const segments = insideSegments(shifted.p1, shifted.p2, polygonPoints)
      if (segments.length === 0) break

      rows.push({ number: rows.length + 1, segments })
    }
  }
  return rows
}

// Куски прямой через lineP1, lineP2 внутри полигона, по порядку вдоль направления lineP1 → lineP2; каждый —
// [конец со стороны lineP1, дальний]. Точки пересечения упорядочены по положению на прямой, а не по расстоянию
// от lineP1: lineP1 может оказаться и внутри участка, и тогда расстояние перемешало бы точки по обе стороны от него.
// Между соседними точками линия либо на участке, либо в выемке снаружи — какой из двух, решает середина куска.
// У выпуклого участка кусок всегда один
function insideSegments(lineP1, lineP2, polygonPoints) {
  const direction = [lineP2[0] - lineP1[0], lineP2[1] - lineP1[1]]
  const along = (point) => (point[0] - lineP1[0]) * direction[0] + (point[1] - lineP1[1]) * direction[1]
  const points = GeometryHelpers.getIntersectionsWithPolygon(lineP1, lineP2, polygonPoints)
    .sort((a, b) => along(a) - along(b))
    .filter((point, i, all) => i === 0 || GeometryHelpers.distance(point, all[i - 1]) > SAME_POINT_DEGREES)

  const segments = []
  for (let i = 0; i + 1 < points.length; i++) {
    const middle = [(points[i][0] + points[i + 1][0]) / 2, (points[i][1] + points[i + 1][1]) / 2]
    if (pointInPolygon(middle, polygonPoints)) segments.push([points[i], points[i + 1]])
  }
  return segments
}

// Луч из точки вдоль параллели: нечётное число пересечений со сторонами — точка внутри
function pointInPolygon([lat, lng], polygonPoints) {
  let inside = false
  for (let i = 0, j = polygonPoints.length - 1; i < polygonPoints.length; j = i++) {
    const [latI, lngI] = polygonPoints[i]
    const [latJ, lngJ] = polygonPoints[j]
    if ((latI > lat) !== (latJ > lat) && lng < (lngJ - lngI) * (lat - latI) / (latJ - latI) + lngI) inside = !inside
  }
  return inside
}

// Куски ряда в порядке нумерации кустов: от опорной вершины (fromFirst — она в начале опорной стороны)
export function orientSegments(segments, fromFirst) {
  return fromFirst ? segments : [...segments].reverse().map(([start, end]) => [end, start])
}

// Кустов на отрезке: первый плюс по одному на каждые bushSpacing метров
export function bushCount(p1, p2, bushSpacing) {
  return Math.floor(GeometryHelpers.kmDistance(p1, p2) * 1000 / bushSpacing) + 1
}

// Кустов в ряду — сумма по его кускам
export function rowBushCount(segments, bushSpacing) {
  return segments.reduce((sum, [start, end]) => sum + bushCount(start, end, bushSpacing), 0)
}

// Кусты вдоль отрезка от start к end: { number, point }, номер с 1 от start
export function bushPoints(start, end, bushSpacing) {
  if (!(bushSpacing > 0)) return [] // иначе шагов бесконечно много
  const steps = bushCount(start, end, bushSpacing) - 1
  const bushes = []
  for (let i = 0; i <= steps; i++) {
    const point = GeometryHelpers.interpolateOnLine([start, end], i / steps)
    if (point) bushes.push({ number: i + 1, point })
  }
  return bushes
}

// Кусты ряда по кускам (уже в порядке orientSegments), номера подряд через все куски
export function rowBushPoints(segments, bushSpacing) {
  const bushes = []
  for (const [start, end] of segments) {
    for (const { point } of bushPoints(start, end, bushSpacing)) bushes.push({ number: bushes.length + 1, point })
  }
  return bushes
}
