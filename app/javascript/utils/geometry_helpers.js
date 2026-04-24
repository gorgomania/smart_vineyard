export class GeometryHelpers {
  // Вычисление расстояния между двумя точками (в км)
  static distance(p1, p2) {
    const R = 6371 // Радиус Земли в км
    const lat1 = p1[0] * Math.PI / 180
    const lat2 = p2[0] * Math.PI / 180
    const deltaLat = (p2[0] - p1[0]) * Math.PI / 180
    const deltaLon = (p2[1] - p1[1]) * Math.PI / 180
    
    const a = Math.sin(deltaLat/2) * Math.sin(deltaLat/2) +
              Math.cos(lat1) * Math.cos(lat2) *
              Math.sin(deltaLon/2) * Math.sin(deltaLon/2)
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
    
    return R * c
  }
  
  // Линейная интерполяция между двумя точками
  static interpolate(p1, p2, t) {
    return [
      p1[0] + (p2[0] - p1[0]) * t,
      p1[1] + (p2[1] - p1[1]) * t
    ]
  }
  
  // Нахождение проекции точки на отрезок
  static projectPointOnLine(p, a, b) {
    const ax = p[1] - a[1]
    const ay = p[0] - a[0]
    const bx = b[1] - a[1]
    const by = b[0] - a[0]
    
    const dot = ax * bx + ay * by
    const len2 = bx * bx + by * by
    
    if (len2 === 0) return a
    
    let t = dot / len2
    t = Math.max(0, Math.min(1, t))
    
    return [
      a[0] + (b[0] - a[0]) * t,
      a[1] + (b[1] - a[1]) * t
    ]
  }
  
  // Нахождение параллельной линии
  static parallelLine(p1, p2, distanceKm, isLeft = true) {
    const R = 6371
    const lat1 = p1[0] * Math.PI / 180
    const lon1 = p1[1] * Math.PI / 180
    const lat2 = p2[0] * Math.PI / 180
    const lon2 = p2[1] * Math.PI / 180
    
    // Направление линии (азимут)
    const dLon = lon2 - lon1
    const y = Math.sin(dLon) * Math.cos(lat2)
    const x = Math.cos(lat1) * Math.sin(lat2) -
              Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon)
    let bearing = Math.atan2(y, x)
    
    // Перпендикулярное направление
    const perpBearing = bearing + (isLeft ? Math.PI / 2 : -Math.PI / 2)
    
    // Смещение в км
    const angularDistance = distanceKm / R
    
    const newLat = Math.asin(Math.sin(lat1) * Math.cos(angularDistance) +
                   Math.cos(lat1) * Math.sin(angularDistance) * Math.cos(perpBearing))
    const newLon = lon1 + Math.atan2(Math.sin(perpBearing) * Math.sin(angularDistance) * Math.cos(lat1),
                   Math.cos(angularDistance) - Math.sin(lat1) * Math.sin(newLat))
    
    return [newLat * 180 / Math.PI, newLon * 180 / Math.PI]
  }
  
  // Проверка, находится ли точка внутри четырёхугольника
  static isPointInPolygon(point, polygon) {
    let inside = false
    for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      const xi = polygon[i][0], yi = polygon[i][1]
      const xj = polygon[j][0], yj = polygon[j][1]
      
      const intersect = ((yi > point[0]) != (yj > point[0])) &&
        (point[1] < (xj - xi) * (point[0] - yi) / (yj - yi) + xi)
      if (intersect) inside = !inside
    }
    return inside
  }

  static calculateArea(polygonPoints) {
    if (!polygonPoints || polygonPoints.length < 3) return 0
    
    let area = 0
    const R = 6371000 // Радиус Земли в метрах
    
    for (let i = 0; i < polygonPoints.length; i++) {
      const j = (i + 1) % polygonPoints.length
      
      const lat1 = polygonPoints[i][0] * Math.PI / 180
      const lat2 = polygonPoints[j][0] * Math.PI / 180
      const lon1 = polygonPoints[i][1] * Math.PI / 180
      const lon2 = polygonPoints[j][1] * Math.PI / 180
      
      area += (lon2 - lon1) * (2 + Math.sin(lat1) + Math.sin(lat2))
    }
    
    area = Math.abs(area * R * R / 2)
    
    // Переводим в гектары (1 га = 10,000 м²)
    return area / 10000
  }

}