import { test, describe } from "node:test"
import assert from "node:assert/strict"
import { polygonSide, layoutRows, orientSegments, bushCount, rowBushCount, bushPoints, rowBushPoints } from "utils/vineyard_rows"
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

      assert.deepEqual(rows[0], { number: 1, segments: [[p1, p2]] })
      assert.ok(rows.length > 1)
      assert.deepEqual(rows.map(r => r.number), rows.map((_, i) => i + 1))

      const direction = [p2[0] - p1[0], p2[1] - p1[1]]
      for (const row of rows.slice(1)) {
        assert.equal(row.segments.length, 1, "у прямоугольника ряд не разрывается")
        const [[a, b]] = row.segments
        const cross = direction[0] * (b[1] - a[1]) - direction[1] * (b[0] - a[0])
        assert.ok(Math.abs(cross) < 1e-12, `ряд ${row.number} не параллелен опорной стороне`)
        assert.ok(onBoundary(a, RECT) && onBoundary(b, RECT), `ряд ${row.number} не на границе`)
      }
    })
  }

  test("ряды покрывают полигон до противоположной стороны и не выходят за неё", () => {
    const rows = layoutRows(RECT, 0, 3)
    const far = rows.reduce((max, r) => Math.max(max, Math.abs(r.segments[0][0][0] - LAT)), 0)
    const step = Math.abs(rows[1].segments[0][0][0] - rows[0].segments[0][0][0])
    assert.ok(far <= 0.0005 + 1e-12, "ряд за противоположной стороной")
    assert.ok(0.0005 - far < step, "до противоположной стороны поместился бы ещё ряд")
  })

  // Неровный четырёхугольник, повёрнутый к сторонам света: ряды идут наискосок
  const SKEWED = [[LAT, LNG], [LAT + 0.0002, LNG + 0.0009], [LAT + 0.0007, LNG + 0.0007], [LAT + 0.0005, LNG - 0.0001], [LAT, LNG]]

  // Расстояние в метрах от точки до прямой через a и b — на местной плоскости вокруг a
  const metersToLine = (p, a, b) => {
    const k = Math.cos(a[0] * Math.PI / 180), m = 6371000 * Math.PI / 180
    const [bx, by, px, py] = [(b[1] - a[1]) * k * m, (b[0] - a[0]) * m, (p[1] - a[1]) * k * m, (p[0] - a[0]) * m]
    return Math.abs(bx * py - by * px) / Math.hypot(bx, by)
  }

  for (const [name, polygon] of [["прямоугольник", RECT], ["косой участок", SKEWED]]) {
    for (const side of [0, 1, 2, 3]) {
      for (const spacing of [2, 3]) {
        test(`${name}, сторона ${side}: ряды ровно через ${spacing} м`, () => {
          const rows = layoutRows(polygon, side, spacing)
          assert.ok(rows.length > 2)
          // Ряд k лежит в (k − 1) × spacing метрах от опорной стороны: и шаг тот, и ряды перпендикулярны ей в метрах
          const [[side1, side2]] = rows[0].segments
          rows.forEach((row, i) => {
            for (const end of row.segments.flat()) {
              const distance = metersToLine(end, side1, side2)
              assert.ok(Math.abs(distance - i * spacing) < 0.01, `ряд ${row.number}: ${distance.toFixed(3)} м вместо ${i * spacing}`)
            }
          })
        })
      }
    }
  }

  // Невыпуклые участки: выемка разрывает линию ряда на куски, ряд один, кусков несколько
  const L_SHAPE = [[LAT, LNG], [LAT, LNG + 0.0012], [LAT + 0.0003, LNG + 0.0012], [LAT + 0.0003, LNG + 0.0005],
    [LAT + 0.0008, LNG + 0.0005], [LAT + 0.0008, LNG], [LAT, LNG]]
  const U_SHAPE = [[LAT, LNG], [LAT, LNG + 0.0004], [LAT + 0.0005, LNG + 0.0004], [LAT + 0.0005, LNG + 0.0008],
    [LAT, LNG + 0.0008], [LAT, LNG + 0.0012], [LAT + 0.0008, LNG + 0.0012], [LAT + 0.0008, LNG], [LAT, LNG]]

  // Точка внутри полигона: луч вдоль параллели
  const inside = ([lat, lng], polygon) => polygon.slice(0, -1).reduce((acc, a, i) => {
    const b = polygon[i + 1]
    return (a[0] > lat) !== (b[0] > lat) && lng < (b[1] - a[1]) * (lat - a[0]) / (b[0] - a[0]) + a[1] ? !acc : acc
  }, false)

  for (const [name, polygon, sides] of [["буква Г", L_SHAPE, 6], ["буква П", U_SHAPE, 8]]) {
    for (let side = 0; side < sides; side++) {
      test(`${name}, сторона ${side}: ряды доходят до конца участка, куски — на участке и по границе`, () => {
        const rows = layoutRows(polygon, side, 3)
        const [[side1, side2]] = rows[0].segments

        for (const row of rows) {
          for (const [a, b] of row.segments) {
            assert.ok(onBoundary(a, polygon) && onBoundary(b, polygon), `ряд ${row.number}: кусок не по границе`)
            assert.ok(inside([(a[0] + b[0]) / 2, (a[1] + b[1]) / 2], polygon) || row.number === 1, `ряд ${row.number}: кусок вне участка`)
            // Шаг: каждый ряд — на целом числе шагов от опорной стороны
            const steps = metersToLine(a, side1, side2) / 3
            assert.ok(Math.abs(steps - Math.round(steps)) < 0.01, `ряд ${row.number}: не на шаге`)
          }
        }

        // Покрытие: до самой дальней вершины меньше шага от последнего ряда
        const farthestVertex = Math.max(...polygon.map(v => metersToLine(v, side1, side2)))
        const farthestRow = Math.max(...rows.flatMap(r => r.segments.flat()).map(p => metersToLine(p, side1, side2)))
        assert.ok(farthestVertex - farthestRow < 3, `не дошли до конца участка: ${farthestRow.toFixed(1)} из ${farthestVertex.toFixed(1)} м`)
      })
    }
  }

  test("буква П: ряд поперёк обеих ножек — один ряд из двух кусков, выемка между ними пустая", () => {
    // Сторона 0 — нижний край левой ножки: ряды вдоль параллели, ниже перемычки линия проходит обе ножки
    const rows = layoutRows(U_SHAPE, 0, 3)
    const broken = rows.filter(r => r.segments.length === 2)
    assert.ok(broken.length > 0, "нет ни одного разорванного ряда")
    assert.ok(rows.every(r => r.segments.length <= 2))
    for (const { segments: [[, leftEnd], [rightStart]] } of broken) {
      // Пробел — ровно выемка: от правого края левой ножки до левого края правой
      assert.ok(Math.abs(leftEnd[1] - (LNG + 0.0004)) < 1e-9 && Math.abs(rightStart[1] - (LNG + 0.0008)) < 1e-9)
    }
  })

  test("шаг рядов не больше нуля — нет рядов, а не бесконечный цикл", () => {
    assert.deepEqual(layoutRows(RECT, 0, 0), [])
    assert.deepEqual(layoutRows(RECT, 0, -3), [])
    assert.deepEqual(layoutRows(RECT, 0, NaN), [])
  })

  test("нет опорной стороны — нет рядов", () => {
    assert.deepEqual(layoutRows(RECT, 7, 3), [])
  })
})

describe("ряд из нескольких кусков", () => {
  const SEGMENTS = [[[LAT, LNG], [LAT, LNG + 0.0002]], [[LAT, LNG + 0.0005], [LAT, LNG + 0.0007]]] // ~16 м, пробел, ~16 м

  test("кустов — сумма по кускам, номера подряд через пробел", () => {
    const count = rowBushCount(SEGMENTS, 1.5)
    assert.equal(count, bushCount(...SEGMENTS[0], 1.5) + bushCount(...SEGMENTS[1], 1.5))

    const bushes = rowBushPoints(SEGMENTS, 1.5)
    assert.equal(bushes.length, count)
    assert.deepEqual(bushes.map(b => b.number), bushes.map((_, i) => i + 1))
    assert.deepEqual(bushes[bushCount(...SEGMENTS[0], 1.5)].point, SEGMENTS[1][0]) // второй кусок начинается с его начала
  })

  test("от другой опорной вершины — куски и их концы в обратном порядке", () => {
    assert.deepEqual(orientSegments(SEGMENTS, true), SEGMENTS)
    assert.deepEqual(orientSegments(SEGMENTS, false), [[SEGMENTS[1][1], SEGMENTS[1][0]], [SEGMENTS[0][1], SEGMENTS[0][0]]])
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

  test("шаг кустов не больше нуля — нет кустов, а не бесконечный цикл", () => {
    assert.deepEqual(bushPoints(start, end, 0), [])
  })

  test("ряд короче шага — один куст на start", () => {
    assert.deepEqual(bushPoints(start, [LAT, LNG + 0.00001], 1.5), [{ number: 1, point: start }])
  })
})
