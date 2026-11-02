import { test, describe, beforeEach } from "node:test"
import assert from "node:assert/strict"

// Окружение браузера и Яндекс Карт — минимальные заглушки (как в heatmap_layer.test.mjs)
globalThis.window = { devicePixelRatio: 1 }
let frames = []
globalThis.requestAnimationFrame = (fn) => frames.push(fn)
globalThis.cancelAnimationFrame = () => {}
const flushFrames = () => { const pending = frames; frames = []; pending.forEach(fn => fn()) }

const projection = {
  toGlobalPixels: ([lat, lng], zoom) => {
    const size = 256 * 2 ** zoom, sin = Math.sin(lat * Math.PI / 180)
    return [(lng + 180) / 360 * size, (0.5 - Math.log((1 + sin) / (1 - sin)) / (4 * Math.PI)) * size]
  }
}

class Layer {
  constructor(tileUrl) {
    this.tileUrl = tileUrl
    this.handlers = {}
    this.events = { add: (type, fn) => { this.handlers[type] = fn }, remove: (type) => { delete this.handlers[type] } }
  }
}
globalThis.ymaps = { Layer, projection: { wgs84Mercator: projection } }

const events = () => {
  const handlers = {}
  return { handlers, add: (type, fn) => { handlers[type] = fn }, remove: (type) => { delete handlers[type] } }
}

function fakeMap(zoom) {
  const hints = []
  return {
    hints,
    getZoom: () => zoom,
    options: { get: () => projection },
    events: events(),
    geoObjects: { events: events() },
    layers: { list: [], add(layer) { this.list.push(layer) }, remove(layer) { this.list = this.list.filter(l => l !== layer) } },
    hint: { open: (coords, text) => hints.push(text), close: () => hints.push(null) }
  }
}

// Контекст canvas, который только записывает вызовы
function recordingContext() {
  const calls = []
  return new Proxy({ calls }, {
    get: (target, name) => name in target ? target[name] : (...args) => calls.push([name, ...args]),
    set: (target, name, value) => { calls.push([`=${String(name)}`, value]); return true }
  })
}

const { RowsLayer, distanceToSegment } = await import("utils/rows_layer")
const { CanvasTileLayer, EMPTY_TILE } = await import("utils/canvas_tile_layer")

const LAT = 44.744, LNG = 33.56
// Два ряда вдоль параллели ~24 м, между ними ~2.2 м; второй ряд из двух кусков (выемка)
const ROWS = [
  { number: 1, segments: [[[LAT, LNG], [LAT, LNG + 0.0003]]], hint: "Ряд 1 · 20 кустов" },
  { number: 2, segments: [[[LAT + 0.00002, LNG], [LAT + 0.00002, LNG + 0.0001]], [[LAT + 0.00002, LNG + 0.0002], [LAT + 0.00002, LNG + 0.0003]]], hint: "Ряд 2 · 14 кустов" }
]

function layer(zoom = 21) {
  const map = fakeMap(zoom)
  const rows = new RowsLayer(map, { color: "#69377c", firstColor: "#FFD700" })
  rows.set(ROWS, ROWS[0].segments[0][0])
  flushFrames()
  return { rows, map }
}

const pixels = (point, zoom) => projection.toGlobalPixels(point, zoom)

beforeEach(() => { frames = [] })

describe("distanceToSegment", () => {
  test("до отрезка — перпендикуляр, за его концом — до конца", () => {
    assert.equal(distanceToSegment(5, 3, 0, 0, 10, 0), 3)
    assert.equal(distanceToSegment(13, 4, 0, 0, 10, 0), 5)
    assert.equal(distanceToSegment(1, 1, 2, 2, 2, 2), Math.SQRT2)
  })
})

describe("RowsLayer: линии и слой", () => {
  test("линия на каждый кусок ряда, слой рисуется раз за кадр", () => {
    const map = fakeMap(21)
    const rows = new RowsLayer(map, { color: "#69377c", firstColor: "#FFD700" })

    rows.set(ROWS, ROWS[0].segments[0][0])
    rows.set(ROWS, ROWS[0].segments[0][0])
    assert.equal(frames.length, 1)
    flushFrames()

    assert.equal(rows.lines.length, 3)
    assert.equal(map.layers.list.length, 1)
  })

  test("тайл без рядов — пустая картинка без canvas", () => {
    const { rows } = layer(21)
    const [x, y] = pixels([LAT, LNG], 21)
    let asked = false

    const drawn = rows.draw(() => { asked = true }, { left: Math.floor(x / 256) * 256 + 256 * 10, top: Math.floor(y / 256) * 256, zoom: 21, ratio: 1 })
    assert.equal(drawn, false)
    assert.equal(asked, false)
  })

  test("тайл с началом рядов: обычные ряды, затем опорная сторона золотом, затем первый куст", () => {
    const { rows } = layer(21)
    const [x, y] = pixels([LAT, LNG], 21)
    const ctx = recordingContext()

    assert.equal(rows.draw(() => ctx, { left: Math.floor(x / 256) * 256, top: Math.floor(y / 256) * 256, zoom: 21, ratio: 2 }), true)

    const colors = ctx.calls.filter(([name]) => name === "=strokeStyle" || name === "=fillStyle").map(([, value]) => value)
    assert.deepEqual(colors, ["#69377c", "#FFD700", "#FFD700", "#FFD700"])
    assert.deepEqual(ctx.calls.find(([name]) => name === "setTransform"), ["setTransform", 2, 0, 0, 2, 0, 0])
    assert.equal(ctx.calls.filter(([name]) => name === "arc").length, 1)
  })
})

describe("RowsLayer#hitTest", () => {
  test("курсор у линии — её ряд, между кусками ряда и далеко от линий — ничего", () => {
    const { rows } = layer(21)

    assert.equal(rows.hitTest(pixels([LAT + 0.00002, LNG + 0.00005], 21)).hint, "Ряд 2 · 14 кустов")
    assert.equal(rows.hitTest(pixels([LAT + 0.00002, LNG + 0.00015], 21)), null) // выемка между кусками ряда 2
    assert.equal(rows.hitTest(pixels([LAT + 0.00001, LNG + 0.00015], 21)), null) // посередине между рядами
  })

  test("у опорной вершины — первый куст", () => {
    const { rows } = layer(21)

    assert.equal(rows.hitTest(pixels([LAT, LNG], 21)).hint, "Первый куст")
  })

  test("круг первого куста — 3 м, но от 4 до 10 px", () => {
    const { rows } = layer(21)

    assert.equal(rows.firstBushRadius(5), 4)
    assert.equal(rows.firstBushRadius(23), 10)
    const metersPerPixel = 156543.034 * Math.cos(LAT * Math.PI / 180) / 2 ** 18
    assert.equal(rows.firstBushRadius(18), 3 / metersPerPixel)
  })

  test("подсказка идёт за курсором и закрывается, когда курсор ушёл с рядов", () => {
    const { rows, map } = layer(21)
    const onRow = (lngOffset) => ({ get: (key) => key === "coords" ? [LAT, LNG + lngOffset] : pixels([LAT, LNG + lngOffset], 21) })

    map.events.handlers.mousemove(onRow(0.0001)); flushFrames()
    map.geoObjects.events.handlers.mousemove(onRow(0.0002)); flushFrames() // над редактируемым полигоном
    map.events.handlers.mousemove({ get: (key) => key === "coords" ? [LAT + 0.00001, LNG + 0.00015] : pixels([LAT + 0.00001, LNG + 0.00015], 21) }); flushFrames()

    assert.deepEqual(map.hints, ["Ряд 1 · 20 кустов", "Ряд 1 · 20 кустов", null])
  })
})

describe("CanvasTileLayer", () => {
  test("пустой тайл — общая прозрачная картинка", () => {
    const tiles = new CanvasTileLayer(fakeMap(10), () => false)
    assert.equal(tiles.tile([1, 2], 10), EMPTY_TILE)
  })

  test("draw получает угол тайла в глобальных пикселях и зум", () => {
    let seen
    new CanvasTileLayer(fakeMap(10), (ctx, tile) => { seen = tile; return false }).tile([3, 4], 12)
    assert.deepEqual(seen, { left: 768, top: 1024, zoom: 12, ratio: 1 })
  })

  test("старый слой снимается, когда новый догрузил тайлы; remove снимает и ждущие", () => {
    const map = fakeMap(10)
    const tiles = new CanvasTileLayer(map, () => false)

    tiles.redraw()
    const first = tiles.layer
    tiles.redraw()
    assert.equal(map.layers.list.length, 2)

    tiles.layer.handlers.tileloadchange({ get: (key) => key === "readyTileNumber" ? 4 : 4 })
    assert.deepEqual(map.layers.list, [tiles.layer])
    assert.ok(!map.layers.list.includes(first))

    tiles.redraw()
    tiles.remove()
    assert.deepEqual(map.layers.list, [])
  })
})
