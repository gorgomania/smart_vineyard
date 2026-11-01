import { test, describe } from "node:test"
import assert from "node:assert/strict"
import { GeometryHelpers as G } from "utils/geometry_helpers"

const close = (actual, expected, tolerance, message) =>
  assert.ok(Math.abs(actual - expected) <= tolerance, `${message ?? ""} ${actual} ≠ ${expected} ± ${tolerance}`)

describe("kmDistance", () => {
  test("градус широты ≈ 111.2 км, градус долготы на 45° ≈ 78.6 км", () => {
    close(G.kmDistance([44, 33], [45, 33]), 111.19, 0.01)
    close(G.kmDistance([45, 33], [45, 34]), 78.63, 0.01)
  })

  test("симметрично и ноль для одной точки", () => {
    assert.equal(G.kmDistance([44.7, 33.5], [44.8, 33.6]), G.kmDistance([44.8, 33.6], [44.7, 33.5]))
    assert.equal(G.kmDistance([44.7, 33.5], [44.7, 33.5]), 0)
  })
})

describe("calculateArea", () => {
  test("квадрат 100 × 100 м ≈ 1 га, обход в любую сторону", () => {
    const dLat = 100 / 111195, dLng = 100 / (111195 * Math.cos(44.744 * Math.PI / 180))
    const square = [[44.744, 33.56], [44.744, 33.56 + dLng], [44.744 + dLat, 33.56 + dLng], [44.744 + dLat, 33.56], [44.744, 33.56]]
    close(G.calculateArea(square), 1, 0.01)
    close(G.calculateArea([...square].reverse()), 1, 0.01)
  })

  test("меньше трёх точек — 0", () => {
    assert.equal(G.calculateArea([[0, 0], [1, 1]]), 0)
    assert.equal(G.calculateArea(null), 0)
  })
})

describe("lineIntersection", () => {
  test("прямая через p1, p2 пересекает отрезок p3–p4", () => {
    assert.deepEqual(G.lineIntersection([0, 0], [1, 1], [0, 2], [2, 0]), [1, 1])
  })

  test("прямая бесконечна: пересечение за пределами p1–p2 тоже считается", () => {
    assert.deepEqual(G.lineIntersection([0, 0], [0.1, 0.1], [0, 2], [2, 0]), [1, 1])
  })

  test("мимо отрезка или параллельно — null", () => {
    assert.equal(G.lineIntersection([0, 0], [1, 1], [3, 0], [4, -1]), null)
    assert.equal(G.lineIntersection([0, 0], [1, 1], [0, 1], [1, 2]), null)
  })
})

test("getIntersectionsWithPolygon: точки по порядку от начала линии", () => {
  const square = [[0, 0], [0, 2], [2, 2], [2, 0], [0, 0]]
  assert.deepEqual(G.getIntersectionsWithPolygon([1, 5], [1, 4], square), [[1, 2], [1, 0]])
})

test("interpolateOnLine: доля пути между двумя точками, NaN — начало", () => {
  assert.deepEqual(G.interpolateOnLine([[0, 0], [2, 4]], 0.5), [1, 2])
  assert.deepEqual(G.interpolateOnLine([[0, 0], [2, 4]], NaN), [0, 0])
  assert.equal(G.interpolateOnLine([[0, 0], [1, 1], [2, 2]], 0.5), null)
})
