import { test, describe, beforeEach } from "node:test"
import assert from "node:assert/strict"

// Окружение браузера и Яндекс Карт — минимальные заглушки: слой рисует тайлы на canvas,
// но индекс кустов, поиск под курсором, размер точек и диагнозы от canvas не зависят
const documentListeners = {}
const dispatched = []
// Canvas без рисования: картинка тайла — уникальная строка, по ней видно, нарисован тайл заново или взят из кэша
let canvasCount = 0
const fakeCanvas = () => ({
  getContext: () => ({ drawImage() {}, beginPath() {}, arc() {}, fill() {}, stroke() {} }),
  toDataURL: () => `data:image/png;base64,tile${++canvasCount}`
})
globalThis.document = {
  createElement: fakeCanvas,
  getElementById: () => null, // нет turbo-stream подписки — слой не ходит за диагнозами сам
  addEventListener: (type, fn) => { documentListeners[type] = fn },
  removeEventListener: (type) => { delete documentListeners[type] },
  dispatchEvent: (event) => dispatched.push(event)
}
globalThis.window = { location: { href: "" }, devicePixelRatio: 1 }
globalThis.getComputedStyle = () => ({ getPropertyValue: () => "#000" }) // цвета диагнозов — из CSS-переменных

let frames = []
globalThis.requestAnimationFrame = (fn) => frames.push(fn)
globalThis.cancelAnimationFrame = () => {}
const flushFrames = () => { const pending = frames; frames = []; pending.forEach(fn => fn()) }

// Сферический Меркатор: глобальные пиксели, 256 на весь мир на нулевом зуме
const projection = {
  toGlobalPixels: ([lat, lng], zoom) => {
    const size = 256 * 2 ** zoom, sin = Math.sin(lat * Math.PI / 180)
    return [(lng + 180) / 360 * size, (0.5 - Math.log((1 + sin) / (1 - sin)) / (4 * Math.PI)) * size]
  },
  fromGlobalPixels: ([x, y], zoom) => {
    const size = 256 * 2 ** zoom
    return [Math.atan(Math.sinh(Math.PI * (1 - 2 * y / size))) * 180 / Math.PI, x / size * 360 - 180]
  }
}

class Layer {
  constructor(tileUrl) {
    this.tileUrl = tileUrl
    this.events = { add() {}, remove() {} }
  }
}
globalThis.ymaps = { Layer, projection: { wgs84Mercator: projection } }

function fakeMap(zoom) {
  const handlers = {}
  return {
    handlers,
    getZoom: () => zoom,
    options: { get: () => projection },
    events: { add: (type, fn) => { handlers[type] = fn } },
    layers: { list: [], add(layer) { this.list.push(layer) }, remove(layer) { this.list = this.list.filter(l => l !== layer) } },
    cursors: { push: () => ({ remove() {} }) },
    hint: { open() {}, close() {} }
  }
}

const { HeatmapLayer, REDRAW_INTERVAL } = await import("utils/heatmap_layer")

// Часы слоя: перерисовка не чаще REDRAW_INTERVAL, время двигаем вручную
const clock = { now: 0 }

const element = { addEventListener() {}, removeEventListener() {} }
const LAT = 44.744, LNG = 33.56
// Ряд вдоль параллели ~23.7 м: при шаге 1.2 м — 20 кустов
const ROW = [[[LAT, LNG], [LAT, LNG + 0.0003]]]

function layout({ zoom = 17, rowSpacing = 2, bushSpacing = 1.2, rows = [ROW], before } = {}) {
  const heatmap = new HeatmapLayer(element, "/vineyards/1/heatmap.json")
  heatmap.now = () => clock.now
  const map = fakeMap(zoom)
  heatmap.attach(map)
  before?.(heatmap)
  heatmap.reset({ rowSpacing, bushSpacing })
  rows.forEach((segments, i) => heatmap.addRow(i + 1, segments))
  heatmap.rendered()
  return { heatmap, map }
}

const pixelsOf = (heatmap, id, zoom) => projection.toGlobalPixels(heatmap.bushById.get(id).coords, zoom)

beforeEach(() => {
  clock.now = 0
  frames = []
  dispatched.length = 0
  window.location.href = ""
})

describe("HeatmapLayer: кусты и диагнозы", () => {
  test("куст на каждую точку ряда, id и подпись «ряд-куст», без диагноза — none", () => {
    const { heatmap } = layout({ rows: [ROW, ROW] })

    assert.equal(heatmap.bushes.length, 40)
    assert.deepEqual(heatmap.bushes.slice(0, 2).map(b => [b.id, b.label, b.key, b.url]),
      [["1-1", "Ряд 1 Куст 1", "none", null], ["1-2", "Ряд 1 Куст 2", "none", null]])
    assert.equal(heatmap.bushes.at(-1).id, "2-20")
  })

  test("диагноз, пришедший до отрисовки, достаётся кусту при раскладке", () => {
    const { heatmap } = layout({ before: h => h.updateBush({ bush: "1-3", mediaItemId: 7, classId: 1 }) })

    const bush = heatmap.bushById.get("1-3")
    assert.equal(bush.key, "esca")
    assert.equal(bush.url, "/media_items/7")
  })

  test("диагноз после отрисовки: куст меняет цвет, слой перерисовывается, легенда пересчитывается", () => {
    const { heatmap, map } = layout()
    flushFrames()
    const layer = heatmap.layer
    dispatched.length = 0

    heatmap.updateBush({ bush: "1-5", mediaItemId: "9", classId: "0" })
    clock.now += REDRAW_INTERVAL
    flushFrames()

    assert.equal(heatmap.bushById.get("1-5").key, "black-rot")
    assert.notEqual(heatmap.layer, layer)
    assert.ok(map.layers.list.includes(heatmap.layer))
    assert.deepEqual(dispatched.at(-1).detail.counts, { none: 19, "black-rot": 1 })
  })

  test("тот же диагноз строками из сообщения и числами из JSON — ничего не перерисовывается", () => {
    const { heatmap } = layout({ before: h => h.updateBush({ bush: "1-1", mediaItemId: 3, classId: 2 }) })
    flushFrames()

    heatmap.updateBush({ bush: "1-1", mediaItemId: "3", classId: "2" })
    assert.equal(frames.length, 0)
  })
})

describe("HeatmapLayer#bushesIn", () => {
  test("возвращает ровно кусты прямоугольника, включая лежащие на его границе", () => {
    const { heatmap } = layout({ rows: [ROW, [[[LAT + 0.00002, LNG], [LAT + 0.00002, LNG + 0.0003]]]] })
    const [a, b] = [heatmap.bushById.get("1-4"), heatmap.bushById.get("2-12")]
    const box = [Math.min(a.x, b.x), Math.min(a.y, b.y), Math.max(a.x, b.x), Math.max(a.y, b.y)]

    const expected = heatmap.bushes.filter(b => b.x >= box[0] && b.x <= box[2] && b.y >= box[1] && b.y <= box[3]).map(b => b.id).sort()
    const found = heatmap.bushesIn(...box).map(b => b.id).sort()

    assert.deepEqual(found, expected)
    assert.ok(found.includes("1-4") && found.includes("2-12"))
    assert.ok(found.length < heatmap.bushes.length)
  })

  test("за пределами участка — пусто", () => {
    const { heatmap } = layout()
    const { x, y } = heatmap.bushes[0]

    assert.deepEqual(heatmap.bushesIn(x + 1, y + 1, x + 2, y + 2), [])
  })
})

describe("HeatmapLayer#hitTest", () => {
  test("курсор на точке — её куст; дальше радиуса точки — ничего", () => {
    const { heatmap } = layout({ zoom: 21 })
    const radius = heatmap.dotSize(21) / 2
    const [x, y] = pixelsOf(heatmap, "1-20", 21)

    assert.equal(heatmap.hitTest([x, y]).id, "1-20")
    assert.equal(heatmap.hitTest([x, y - radius + 0.5]).id, "1-20")
    assert.equal(heatmap.hitTest([x, y - radius - 0.5]), null)
  })

  test("точки перекрываются — берём больной куст, он нарисован сверху", () => {
    // Зум 17: кусты в 1.2 м — это ~1.4 px, точка 4 px — соседние точки накрывают друг друга
    const { heatmap } = layout({ zoom: 17, before: h => h.updateBush({ bush: "1-6", mediaItemId: 1, classId: 3 }) })

    assert.equal(heatmap.hitTest(pixelsOf(heatmap, "1-5", 17)).id, "1-6")
  })

  test("скрытый в легенде диагноз под курсором не находится", () => {
    const { heatmap } = layout({ zoom: 17, before: h => h.updateBush({ bush: "1-6", mediaItemId: 1, classId: 3 }) })

    documentListeners["heatmap:filter"]({ detail: { hidden: ["leaf-blight"] } })
    assert.equal(heatmap.hitTest(pixelsOf(heatmap, "1-6", 17)).key, "none")

    documentListeners["heatmap:filter"]({ detail: { hidden: ["leaf-blight", "none"] } })
    assert.equal(heatmap.hitTest(pixelsOf(heatmap, "1-6", 17)), null)
  })

  test("клик по кусту с файлом открывает файл, по кусту без файла — никуда", () => {
    const { heatmap, map } = layout({ zoom: 21, before: h => h.updateBush({ bush: "1-2", mediaItemId: 42, classId: 2 }) })

    map.handlers.click({ get: () => pixelsOf(heatmap, "1-1", 21) })
    assert.equal(window.location.href, "")

    map.handlers.click({ get: () => pixelsOf(heatmap, "1-2", 21) })
    assert.equal(window.location.href, "/media_items/42")
  })
})

describe("HeatmapLayer#dotSize", () => {
  test("от 4 до 14 px, между ними — 0.9 расстояния между кустами", () => {
    const { heatmap } = layout()

    assert.equal(heatmap.dotSize(10), 4)
    assert.equal(heatmap.dotSize(23), 14)

    const metersPerPixel = 156543.034 * Math.cos(heatmap.latitude * Math.PI / 180) / 2 ** 20
    assert.equal(heatmap.dotSize(20), Math.round(1.2 / metersPerPixel * 0.9))
  })
})

describe("HeatmapLayer#drawTile", () => {
  test("тайл без кустов и тайл, где все кусты скрыты, — общий прозрачный пиксель без canvas", () => {
    const { heatmap } = layout({ zoom: 17 })
    const [x, y] = pixelsOf(heatmap, "1-1", 17)
    const tile = [Math.floor(x / 256), Math.floor(y / 256)]

    const empty = heatmap.drawTile([tile[0] + 5, tile[1] + 5], 17)
    assert.match(empty, /^data:image\/gif/)

    documentListeners["heatmap:filter"]({ detail: { hidden: ["none"] } })
    assert.equal(heatmap.drawTile(tile, 17), empty)
  })
})

describe("HeatmapLayer: перерисовка при классификации", () => {
  // На 22-м зуме ряд ~23.7 м — около 900 px: первый и последний куст на разных тайлах
  const tileOf = (heatmap, id) => {
    const [x, y] = pixelsOf(heatmap, id, 22)
    return [Math.floor(x / 256), Math.floor(y / 256)]
  }

  test("перекрашенный куст — заново только его тайл, остальные берутся готовыми", () => {
    const { heatmap } = layout({ zoom: 22 })
    const first = tileOf(heatmap, "1-1"), last = tileOf(heatmap, "1-20")
    assert.notDeepEqual(first, last)
    const before = [heatmap.drawTile(first, 22), heatmap.drawTile(last, 22)]

    heatmap.updateBush({ bush: "1-1", mediaItemId: "9", classId: "0" })
    clock.now += REDRAW_INTERVAL
    flushFrames()

    assert.notEqual(heatmap.drawTile(first, 22), before[0])
    assert.equal(heatmap.drawTile(last, 22), before[1])
  })

  test("фильтр легенды перерисовывает все тайлы", () => {
    const { heatmap } = layout({ zoom: 22 })
    const last = tileOf(heatmap, "1-20")
    const before = heatmap.drawTile(last, 22)

    documentListeners["heatmap:filter"]({ detail: { hidden: ["healthy"] } })
    clock.now += REDRAW_INTERVAL
    flushFrames()

    assert.notEqual(heatmap.drawTile(last, 22), before)
  })

  test("поток результатов — слой меняется не чаще REDRAW_INTERVAL, все изменения попадают в одну перерисовку", () => {
    const { heatmap } = layout({ zoom: 22 })
    const first = tileOf(heatmap, "1-1"), last = tileOf(heatmap, "1-20")
    const before = [heatmap.drawTile(first, 22), heatmap.drawTile(last, 22)]
    const layer = heatmap.layer

    heatmap.updateBush({ bush: "1-1", mediaItemId: "9", classId: "0" })
    flushFrames()
    heatmap.updateBush({ bush: "1-20", mediaItemId: "10", classId: "1" })
    flushFrames()
    assert.equal(heatmap.layer, layer) // интервал не прошёл — ждём

    clock.now += REDRAW_INTERVAL
    flushFrames()
    assert.notEqual(heatmap.layer, layer)
    assert.notEqual(heatmap.drawTile(first, 22), before[0])
    assert.notEqual(heatmap.drawTile(last, 22), before[1])
  })
})
