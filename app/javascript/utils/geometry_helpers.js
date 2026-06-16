export class GeometryHelpers {
  // Вычисление расстояния между двумя точками (в км)
  static kmDistance(p1, p2) {
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

  static metersToDegrees(meters, polygonPoint) {
    // 1 градус широты ≈ 111320 метров (всегда)
    const metersPerDegreeLat = 111320
    
    // 1 градус долготы зависит от широты
    const metersPerDegreeLon = 111320 * Math.cos(polygonPoint * Math.PI / 180)
    
    // Для рядов используем среднее (ряды могут идти в любом направлении)
    const avgMetersPerDegree = (metersPerDegreeLat + metersPerDegreeLon) / 2
    
    return meters / avgMetersPerDegree
  }

  static distance(p1, p2) {
    return Math.sqrt((p1[0] - p2[0])**2 + (p1[1] - p2[1])**2)
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

  // Смещение линии
  static shiftLine(p1, p2, perpUnit, offset) {
    return {
      p1: [p1[0] + perpUnit[0] * offset, p1[1] + perpUnit[1] * offset],
      p2: [p2[0] + perpUnit[0] * offset, p2[1] + perpUnit[1] * offset]
    }
  }

  // Поиск пересечений линии с полигоном
  static getIntersectionsWithPolygon(lineP1, lineP2, polygonPoints) {
    const intersections = []

    for (let i = 0; i < polygonPoints.length - 1; i++) {
      const intersection = this.lineIntersection(
        lineP1, lineP2,
        polygonPoints[i], polygonPoints[i + 1]
      )

      if (intersection) {
        intersections.push(intersection)
      }
    }
    
    return intersections.sort((a, b) => this.distance(lineP1, a) - this.distance(lineP1, b))
  }
  
  static lineIntersection(p1, p2, p3, p4) {
      const denominator = (p4[1] - p3[1]) * (p2[0] - p1[0]) - (p4[0] - p3[0]) * (p2[1] - p1[1])
      if (denominator === 0) return null // Прямая и отрезок параллельны
      
      const ua = ((p4[0] - p3[0]) * (p1[1] - p3[1]) - (p4[1] - p3[1]) * (p1[0] - p3[0])) / denominator
      const ub = ((p2[0] - p1[0]) * (p1[1] - p3[1]) - (p2[1] - p1[1]) * (p1[0] - p3[0])) / denominator
      
      // ub проверяем (пересечение с отрезком), ua не проверяем (прямая бесконечна)
      if (ub < 0 || ub > 1) return null
      
      return [
        p1[0] + ua * (p2[0] - p1[0]),
        p1[1] + ua * (p2[1] - p1[1])
      ]
  }

 static interpolateOnLine(points, t) {
    // Если всего 2 точки - просто интерполируем между ними
    if (points.length === 2) {
      if (isNaN(t)) {
        t = 0
      }
      return [
        points[0][0] + (points[1][0] - points[0][0]) * t,
        points[0][1] + (points[1][1] - points[0][1]) * t
      ]
    }
    else {
      return null
    } 
  }
}