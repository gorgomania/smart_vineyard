// Свой тайловый слой Яндекс Карт: каждый тайл 256×256 рисуем на canvas и отдаём картинкой (data: URL).
// Объекты Яндекса (метки, линии) на сотнях тысяч кустов рисуются минутами, а сотни длинных рядов на большом зуме
// при дробном масштабе экрана (Windows 125–150 %) теряют куски — свои тайлы не зависят ни от того, ни от другого.
// Что рисовать, решает draw(ctx, tile): tile.left/top — глобальные пиксели угла тайла на зуме tile.zoom,
// ctx() — контекст по требованию (пустой тайл canvas не создаёт), вернуть true, если что-то нарисовано
export const TILE = 256
export const EMPTY_TILE = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'
// Готовых тайлов храним столько: несколько экранов на нескольких зумах. Сверх — вытесняем самые давние
export const CACHE_LIMIT = 512

export class CanvasTileLayer {
  constructor(map, draw, { pane = 'places' } = {}) {
    this.map = map
    this.draw = draw
    this.pane = pane
    this.layer = null
    this.pendingSwaps = new Set() // старые слои, ждущие, пока новый догрузит тайлы
    // Готовые тайлы «зум/x/y/ratio» → картинка. Новый слой берёт их отсюда: рисовать и кодировать в PNG
    // все видимые тайлы ради пары изменившихся точек — то, из-за чего карта дёргалась при классификации
    this.cache = new Map()
  }

  // Тайл — картинка. На экранах с плотными пикселями рисуем крупнее (ratio): Яндекс сожмёт тайл до 256 точек
  tile([tx, ty], zoom) {
    const ratio = Math.min(2, Math.ceil(window.devicePixelRatio || 1))
    const key = `${zoom}/${tx}/${ty}/${ratio}`
    const cached = this.cache.get(key)
    if (cached !== undefined) {
      this.cache.delete(key) // в конец очереди: недавно нужные вытесняются последними
      this.cache.set(key, cached)
      return cached
    }

    let canvas = null
    const ctx = () => {
      if (!canvas) {
        canvas = document.createElement('canvas')
        canvas.width = canvas.height = TILE * ratio
      }
      return canvas.getContext('2d')
    }
    const drawn = this.draw(ctx, { left: tx * TILE, top: ty * TILE, zoom, ratio })
    const url = drawn && canvas ? canvas.toDataURL() : EMPTY_TILE
    this.cache.set(key, url)
    if (this.cache.size > CACHE_LIMIT) this.cache.delete(this.cache.keys().next().value)
    return url
  }

  // Изменилось всё (раскладка, фильтр): все тайлы рисуются заново
  redraw() {
    this.cache.clear()
    this.replaceLayer()
  }

  // Изменились отдельные точки: заново рисуются только задетые тайлы — touches(zoom, left, top), угол тайла
  // в глобальных пикселях его зума. Остальные новый слой возьмёт готовыми
  redrawTiles(touches) {
    for (const key of [ ...this.cache.keys() ]) {
      const [ zoom, tx, ty ] = key.split('/').map(Number)
      if (touches(zoom, tx * TILE, ty * TILE)) this.cache.delete(key)
    }
    this.replaceLayer()
  }

  // Новый слой на место старого. Старый снимаем, когда новый догрузил тайлы, — иначе картинка на миг пропадает
  replaceLayer() {
    const old = this.layer
    const layer = this.layer = new ymaps.Layer((tile, zoom) => this.tile(tile, zoom), { tileTransparent: true, pane: this.pane })

    if (old) {
      const pending = { old, swap: () => {
        clearTimeout(pending.timer)
        layer.events.remove('tileloadchange', onLoad)
        this.pendingSwaps.delete(pending)
        this.map.layers.remove(old)
      } }
      const onLoad = (e) => {
        if (e.get('readyTileNumber') >= e.get('totalTileNumber')) pending.swap()
      }
      pending.timer = setTimeout(pending.swap, 1000)
      layer.events.add('tileloadchange', onLoad)
      this.pendingSwaps.add(pending)
    }
    this.map.layers.add(layer)
  }

  // Снять с карты и текущий слой, и старые, ещё ждущие смены
  remove() {
    this.pendingSwaps.forEach(pending => pending.swap())
    if (this.layer) this.map.layers.remove(this.layer)
    this.layer = null
  }
}
