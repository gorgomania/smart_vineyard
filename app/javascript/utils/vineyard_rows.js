// Раскладка виноградника без Яндекс Карт: ряды по полигону и кусты вдоль ряда.
// Точки — [lat, lng], как в геометрии полигона на карте
import { GeometryHelpers } from "utils/geometry_helpers"

// Опорная сторона полигона: от вершины index к следующей
export function polygonSide(points, index) {
  if (!points || points.length < 2 || index >= points.length - 1 || index < 0) return null
  return { p1: points[index], p2: points[index + 1] }
}

// Первый ряд — опорная сторона, остальные параллельно ей через rowSpacing метров: сначала в одну сторону,
// потом в другую, пока линия пересекает полигон. Номер ряда — порядок обхода (так их считает и форма)
export function layoutRows(polygonPoints, sideIndex, rowSpacing) {
  const first = polygonSide(polygonPoints, sideIndex)
  if (!first) return []

  // Единичный перпендикуляр к первому ряду — направление смещения
  const rowVector = [first.p2[0] - first.p1[0], first.p2[1] - first.p1[1]]
  const perpVector = [-rowVector[1], rowVector[0]]
  const perpLength = Math.sqrt(perpVector[0] ** 2 + perpVector[1] ** 2)
  const perpUnit = [perpVector[0] / perpLength, perpVector[1] / perpLength]
  const stepDeg = GeometryHelpers.metersToDegrees(rowSpacing, polygonPoints[0][0])

  const rows = [{ number: 1, p1: first.p1, p2: first.p2 }]
  for (const direction of [1, -1]) {
    for (let offset = direction * stepDeg; ; offset += direction * stepDeg) {
      const shifted = GeometryHelpers.shiftLine(first.p1, first.p2, perpUnit, offset)
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
