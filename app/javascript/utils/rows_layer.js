// Ряды виноградника линиями (просмотр без тепловой карты, создание и правка): по линии на кусок ряда,
// опорная сторона (ряд 1) и первый куст — золотые. Свой тайловый слой (utils/canvas_tile_layer), а не ymaps.Polyline:
// сотни рядов по километру на большом зуме при масштабе экрана 150 % Яндекс рисовал с пропусками — целые куски
// рядов исчезали. Подсказку «Ряд N · M кустов» ищем сами: ближайшая линия под курсором (hitTest)
import { CanvasTileLayer, TILE } from "utils/canvas_tile_layer"

const ROW_STYLE = { width: 2, opacity: 0.8 }
const FIRST_ROW_STYLE = { width: 4, opacity: 0.9 }
// Первый куст — круг радиусом 3 м, но на экране не меньше и не больше этих пикселей: на общем плане его видно,
// а на большом зуме он не закрывает начало рядов
const FIRST_BUSH = { meters: 3, minPx: 4, maxPx: 10, opacity: 0.8 }
// Насколько далеко от линии курсор ещё «на ряду», px
const HIT_PX = 4

export class RowsLayer {
  constructor(map, { color, firstColor }) {
    this.map = map
    this.color = color
    this.firstColor = firstColor
    this.projection = map.options.get('projection') || ymaps.projection.wgs84Mercator
    this.tiles = new CanvasTileLayer(map, (ctx, tile) => this.draw(ctx, tile))
    this.lines = []
    this.firstBush = null

    // Над редактируемым полигоном события идут ему, а не карте: слушаем и map.geoObjects, куда они всплывают
    this.onMove = (e) => {
      this.hoverEvent = { pixels: e.get('globalPixels'), coords: e.get('coords') }
      if (this.hoverFrame) return
      this.hoverFrame = requestAnimationFrame(() => {
        this.hoverFrame = null
        if (this.hoverEvent) this.hover(this.hitTest(this.hoverEvent.pixels), this.hoverEvent.coords)
      })
    }
    this.onLeave = () => {
      this.hoverEvent = null
      this.hover(null)
    }
    for (const events of [map.events, map.geoObjects.events]) {
      events.add('mousemove', this.onMove)
      events.add('mouseleave', this.onLeave)
    }
  }

  destroy() {
    cancelAnimationFrame(this.redrawFrame)
    cancelAnimationFrame(this.hoverFrame)
    for (const events of [this.map.events, this.map.geoObjects.events]) {
      events.remove('mousemove', this.onMove)
      events.remove('mouseleave', this.onLeave)
    }
    this.tiles.remove()
  }

  // rows — [{ number, segments, hint }] (куски ряда — [[lat, lng], [lat, lng]]), firstBush — [lat, lng].
  // Полигон тянут — ряды приходят на каждое его изменение, слой перерисовываем раз за кадр
  set(rows, firstBush) {
    const toPixels = (point) => this.projection.toGlobalPixels(point, 0)
    this.lines = rows.flatMap(({ number, segments, hint }) => segments.map(([p1, p2]) => {
      const [x1, y1] = toPixels(p1), [x2, y2] = toPixels(p2)
      return { number, hint, x1, y1, x2, y2,
               minX: Math.min(x1, x2), maxX: Math.max(x1, x2), minY: Math.min(y1, y2), maxY: Math.max(y1, y2) }
    }))
    this.firstBush = firstBush ? { coords: firstBush, ...Object.fromEntries(['x', 'y'].map((k, i) => [k, toPixels(firstBush)[i]])) } : null
    this.latitude = firstBush?.[0] ?? 0

    if (this.redrawFrame) return
    this.redrawFrame = requestAnimationFrame(() => {
      this.redrawFrame = null
      this.tiles.redraw()
    })
  }

  // Радиус первого куста в пикселях на зуме zoom
  firstBushRadius(zoom) {
    const metersPerPixel = 156543.034 * Math.cos(this.latitude * Math.PI / 180) / 2 ** zoom
    return Math.min(FIRST_BUSH.maxPx, Math.max(FIRST_BUSH.minPx, FIRST_BUSH.meters / metersPerPixel))
  }

  // Ряды, задевающие тайл (линии рисуем с запасом на толщину: иначе на стыке тайлов край линии срезан)
  draw(ctx, { left, top, zoom, ratio }) {
    const scale = 2 ** zoom
    const pad = (FIRST_ROW_STYLE.width + this.firstBushRadius(zoom)) / scale
    const x1 = left / scale - pad, y1 = top / scale - pad, x2 = (left + TILE) / scale + pad, y2 = (top + TILE) / scale + pad
    const lines = this.lines.filter(l => l.maxX >= x1 && l.minX <= x2 && l.maxY >= y1 && l.minY <= y2)
    const bush = this.firstBush
    const bushHere = bush && bush.x >= x1 && bush.x <= x2 && bush.y >= y1 && bush.y <= y2
    if (!lines.length && !bushHere) return false

    const context = ctx()
    context.setTransform(ratio, 0, 0, ratio, 0, 0)
    context.lineCap = 'round'
    const px = (x, y) => [x * scale - left, y * scale - top]

    // Опорная сторона — поверх остальных рядов
    for (const first of [false, true]) {
      const style = first ? FIRST_ROW_STYLE : ROW_STYLE
      context.beginPath()
      for (const line of lines) {
        if ((line.number === 1) !== first) continue
        context.moveTo(...px(line.x1, line.y1))
        context.lineTo(...px(line.x2, line.y2))
      }
      context.lineWidth = style.width
      context.globalAlpha = style.opacity
      context.strokeStyle = first ? this.firstColor : this.color
      context.stroke()
    }

    if (bushHere) {
      context.beginPath()
      context.arc(...px(bush.x, bush.y), this.firstBushRadius(zoom), 0, 2 * Math.PI)
      context.globalAlpha = FIRST_BUSH.opacity
      context.fillStyle = this.firstColor
      context.fill()
      context.globalAlpha = 1
      context.lineWidth = 2
      context.strokeStyle = this.firstColor
      context.stroke()
    }
    return true
  }

  // Что под курсором (глобальные пиксели текущего зума): первый куст, иначе ближайший ряд не дальше HIT_PX от линии
  hitTest(pixels) {
    if (!pixels) return null
    const zoom = this.map.getZoom()
    const scale = 2 ** zoom
    const [x, y] = pixels

    const bush = this.firstBush
    if (bush && Math.hypot(bush.x * scale - x, bush.y * scale - y) <= this.firstBushRadius(zoom)) {
      return { hint: 'Первый куст' }
    }

    let best = null, bestDistance = Infinity
    for (const line of this.lines) {
      const reach = HIT_PX + (line.number === 1 ? FIRST_ROW_STYLE : ROW_STYLE).width / 2
      const distance = distanceToSegment(x, y, line.x1 * scale, line.y1 * scale, line.x2 * scale, line.y2 * scale)
      if (distance <= reach && distance < bestDistance) {
        best = line
        bestDistance = distance
      }
    }
    return best
  }

  // Ряд длинный — подсказка идёт за курсором, как у линий Яндекса
  hover(target, coords) {
    const hint = target?.hint ?? null
    if (hint && coords) this.map.hint.open(coords, hint)
    else if (this.hoveredHint) this.map.hint.close()
    this.hoveredHint = hint
  }
}

// Расстояние от точки до отрезка, в тех же единицах
export function distanceToSegment(px, py, x1, y1, x2, y2) {
  const dx = x2 - x1, dy = y2 - y1
  const lengthSquared = dx * dx + dy * dy
  const t = lengthSquared ? Math.max(0, Math.min(1, ((px - x1) * dx + (py - y1) * dy) / lengthSquared)) : 0
  return Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))
}
