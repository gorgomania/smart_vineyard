import { test } from "node:test"
import assert from "node:assert/strict"
import { parseWKT } from "utils/wkt"

test("WKT из базы (lng lat) в координаты Яндекс Карт (lat lng)", () => {
  assert.deepEqual(
    parseWKT("POLYGON((33.56 44.744, 33.561 44.744, 33.561 44.7445, 33.56 44.744))"),
    [[44.744, 33.56], [44.744, 33.561], [44.7445, 33.561], [44.744, 33.56]]
  )
})

test("пробел после POLYGON и регистр не важны", () => {
  assert.deepEqual(parseWKT("polygon ((1 2, 3 4, 5 6, 1 2))"), [[2, 1], [4, 3], [6, 5], [2, 1]])
})

test("не полигон — null", (t) => {
  t.mock.method(console, "error", () => {})
  assert.equal(parseWKT("POINT(33.56 44.744)"), null)
})
