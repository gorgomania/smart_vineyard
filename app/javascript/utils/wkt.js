// Полигон из базы в WKT — "POLYGON((lng lat, lng lat, ...))" или "POLYGON ((...))" —
// в координаты Яндекс Карт [[lat, lng], ...]
export function parseWKT(wkt) {
  const match = wkt.match(/POLYGON\s*\(\((.+)\)\)/i)
  if (!match) {
    console.error('Invalid WKT format:', wkt)
    return null
  }

  return match[1].split(', ').map(point => {
    const [lng, lat] = point.split(' ')
    return [parseFloat(lat), parseFloat(lng)]
  })
}
