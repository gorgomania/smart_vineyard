import { test, describe } from "node:test"
import assert from "node:assert/strict"
import { polygonSide, layoutRows, bushCount, bushPoints } from "utils/vineyard_rows"
import { GeometryHelpers } from "utils/geometry_helpers"

const meters = (a, b) => GeometryHelpers.kmDistance(a, b) * 1000

// Прямоугольник ~79 × 56 м под Севастополем, замкнутый, как его отдают Яндекс Карты: [lat, lng]
const LAT = 44.744, LNG = 33.56
const RECT = [[LAT, LNG], [LAT, LNG + 0.001], [LAT + 0.0005, LNG + 0.001], [LAT + 0.0005, LNG], [LAT, LNG]]

// Точка лежит на границе полигона (на одной из его сторон)
const onBoundary = (p, polygon) => polygon.slice(0, -1).some((a, i) => {
  const b = polygon[i + 1]
  return Math.abs(meters(a, p) + meters(p, b) - meters(a, b)) < 0.01
})

describe("polygonSide", () => {
  test("сторона — вершина и следующая за ней", () => {
    assert.deepEqual(polygonSide(RECT, 0), { p1: RECT[0], p2: RECT[1] })
    assert.deepEqual(polygonSide(RECT, 3), { p1: RECT[3], p2: RECT[4] })
  })

  test("за пределами сторон — null", () => {
    assert.equal(polygonSide(RECT, -1), null)
    assert.equal(polygonSide(RECT, 4), null) // RECT[4] — замыкающая точка, стороны 4 нет
    assert.equal(polygonSide([RECT[0]], 0), null)
  })
})

describe("layoutRows", () => {
  for (const side of [0, 1, 2, 3]) {
    // Перпендикуляр смотрит наружу или внутрь в зависимости от стороны — ряды всё равно идут внутрь участка
    test(`опорная сторона ${side}: первый ряд — она сама, остальные параллельны и упираются в границу`, () => {
      const rows = layoutRows(RECT, side, 3)
      const { p1, p2 } = polygonSide(RECT, side)

      assert.deepEqual(rows[0], { number: 1, p1, p2 })
      assert.ok(rows.length > 1)
      assert.deepEqual(rows.map(r => r.number), rows.map((_, i) => i + 1))

      const direction = [p2[0] - p1[0], p2[1] - p1[1]]
      for (const row of rows.slice(1)) {
        const cross = direction[0] * (row.p2[1] - row.p1[1]) - direction[1] * (row.p2[0] - row.p1[0])
        assert.ok(Math.abs(cross) < 1e-12, `ряд ${row.number} не параллелен опорной стороне`)
        assert.ok(onBoundary(row.p1, RECT) && onBoundary(row.p2, RECT), `ряд ${row.number} не на границе`)
      }
    })
  }

  test("ряды покрывают полигон до противоположной стороны и не выходят за неё", () => {
    const rows = layoutRows(RECT, 0, 3)
    const far = rows.reduce((max, r) => Math.max(max, Math.abs(r.p1[0] - LAT)), 0)
    const step = Math.abs(rows[1].p1[0] - rows[0].p1[0])
    assert.ok(far <= 0.0005 + 1e-12, "ряд за противоположной стороной")
    assert.ok(0.0005 - far < step, "до противоположной стороны поместился бы ещё ряд")
  })

  test("нет опорной стороны — нет рядов", () => {
    assert.deepEqual(layoutRows(RECT, 7, 3), [])
  })
})

describe("bushCount", () => {
  test("первый куст плюс по одному на каждый полный шаг", () => {
    const start = [LAT, LNG], end = [LAT, LNG + 0.001] // ~79 м
    const length = meters(start, end)
    assert.equal(bushCount(start, end, 1.5), Math.floor(length / 1.5) + 1)
    assert.equal(bushCount(start, end, 100), 1)
  })

  test("не зависит от направления ряда", () => {
    assert.equal(bushCount(RECT[0], RECT[1], 1.5), bushCount(RECT[1], RECT[0], 1.5))
  })
})

describe("bushPoints", () => {
  const start = [LAT, LNG], end = [LAT, LNG + 0.001]

  test("кустов столько же, сколько считает bushCount, номера с 1", () => {
    const bushes = bushPoints(start, end, 1.5)
    assert.equal(bushes.length, bushCount(start, end, 1.5))
    assert.deepEqual(bushes.map(b => b.number), bushes.map((_, i) => i + 1))
  })

  test("первый куст — на start, последний — на end, нумерация от start", () => {
    const bushes = bushPoints(start, end, 1.5)
    assert.deepEqual(bushes[0].point, start)
    assert.ok(meters(bushes.at(-1).point, end) < 1e-6)
    assert.deepEqual(bushPoints(end, start, 1.5)[0].point, end)
  })

  test("кусты на равном расстоянии друг от друга", () => {
    const bushes = bushPoints(start, end, 1.5)
    const gaps = bushes.slice(1).map((b, i) => meters(bushes[i].point, b.point))
    assert.ok(Math.max(...gaps) - Math.min(...gaps) < 1e-6)
    assert.ok(gaps[0] >= 1.5, "куст ближе заданного шага")
  })

  test("ряд короче шага — один куст на start", () => {
    assert.deepEqual(bushPoints(start, [LAT, LNG + 0.00001], 1.5), [{ number: 1, point: start }])
  })
})
