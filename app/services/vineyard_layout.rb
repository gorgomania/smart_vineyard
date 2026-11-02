# Раскладка рядов и кустов по полигону виноградника — серверная копия app/javascript/utils/vineyard_rows.js
# (и нужных ей GeometryHelpers). Карта считает её, чтобы показать ряды и числа в форме; по этой копии сервер
# создаёт ряды и кусты при сохранении (числам из браузера не верит) и пересчитывает виноградники без браузера.
# Повторяет JS операция в операцию, чтобы числа совпадали до куста: общие эталоны —
# spec/fixtures/files/vineyard_layouts.json, их проверяют и spec/services/vineyard_layout_spec.rb, и spec/javascript
class VineyardLayout
  EARTH_RADIUS_KM = 6371
  METERS_PER_DEGREE = 6_371_000 * Math::PI / 180

  # points — замкнутый контур [[lat, lng], ...], как в JS
  def self.for(vineyard)
    points = vineyard.polygon.exterior_ring.points.map { |p| [ p.y, p.x ] }
    new(points, side_index: vineyard.reference_side_index, row_spacing: vineyard.row_spacing.to_f,
                bush_spacing: vineyard.bush_spacing.to_f)
  end

  def initialize(points, side_index:, row_spacing:, bush_spacing:)
    @points = points
    @side_index = side_index
    @row_spacing = row_spacing
    @bush_spacing = bush_spacing
  end

  # Число кустов в каждом ряду по порядку номеров
  def bushes_per_row
    rows.map { |p1, p2| bush_count(p1, p2) }
  end

  # Площадь участка в гектарах на сфере R = 6371 км (GeometryHelpers.calculateArea)
  def area_hectares
    radius = EARTH_RADIUS_KM * 1000
    # inject, а не sum: sum складывает с компенсацией (Кэхэн–Бабушка), а JS — обычным +=
    area = @points.each_index.inject(0.0) do |acc, i|
      lat1, lon1 = @points[i].map { |deg| deg * Math::PI / 180 }
      lat2, lon2 = @points[(i + 1) % @points.size].map { |deg| deg * Math::PI / 180 }
      acc + (lon2 - lon1) * (2 + Math.sin(lat1) + Math.sin(lat2))
    end
    (area * radius * radius / 2).abs / 10_000
  end

  # [[p1, p2], ...]: первый — опорная сторона, затем параллельные через row_spacing метров в одну сторону,
  # потом в другую, пока линия пересекает полигон (layoutRows)
  def rows
    first = polygon_side
    return [] unless first

    p1, p2 = first
    meters_per_degree_lat = METERS_PER_DEGREE
    meters_per_degree_lng = METERS_PER_DEGREE * Math.cos(@points[0][0] * Math::PI / 180)
    north = (p2[0] - p1[0]) * meters_per_degree_lat
    east = (p2[1] - p1[1]) * meters_per_degree_lng
    length = Math.sqrt(north * north + east * east)
    perp_per_meter = [ -east / length / meters_per_degree_lat, north / length / meters_per_degree_lng ]

    rows = [ first ]
    [ 1, -1 ].each do |direction|
      offset = direction * @row_spacing
      loop do
        shifted = shift_line(p1, p2, perp_per_meter, offset)
        intersections = intersections_with_polygon(*shifted)
        break unless intersections.size == 2

        rows << intersections
        offset += direction * @row_spacing
      end
    end
    rows
  end

  private

  def polygon_side
    return if @points.size < 2 || @side_index >= @points.size - 1 || @side_index.negative?

    [ @points[@side_index], @points[@side_index + 1] ]
  end

  def bush_count(p1, p2)
    (km_distance(p1, p2) * 1000 / @bush_spacing).floor + 1
  end

  # Гаверсинус на сфере R = 6371 км (GeometryHelpers.kmDistance)
  def km_distance(p1, p2)
    lat1 = p1[0] * Math::PI / 180
    lat2 = p2[0] * Math::PI / 180
    delta_lat = (p2[0] - p1[0]) * Math::PI / 180
    delta_lon = (p2[1] - p1[1]) * Math::PI / 180

    a = Math.sin(delta_lat / 2) * Math.sin(delta_lat / 2) +
        Math.cos(lat1) * Math.cos(lat2) *
        Math.sin(delta_lon / 2) * Math.sin(delta_lon / 2)
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

    EARTH_RADIUS_KM * c
  end

  def shift_line(p1, p2, perp, offset)
    [ [ p1[0] + perp[0] * offset, p1[1] + perp[1] * offset ],
      [ p2[0] + perp[0] * offset, p2[1] + perp[1] * offset ] ]
  end

  # Пересечения прямой через line_p1, line_p2 со сторонами полигона, от line_p1 по порядку
  def intersections_with_polygon(line_p1, line_p2)
    found = @points.each_cons(2).filter_map { |p3, p4| line_intersection(line_p1, line_p2, p3, p4) }
    found.sort_by.with_index { |point, i| [ distance(line_p1, point), i ] }
  end

  # Прямая через p1, p2 (бесконечная) и отрезок p3–p4
  def line_intersection(p1, p2, p3, p4)
    denominator = (p4[1] - p3[1]) * (p2[0] - p1[0]) - (p4[0] - p3[0]) * (p2[1] - p1[1])
    return if denominator.zero?

    ua = ((p4[0] - p3[0]) * (p1[1] - p3[1]) - (p4[1] - p3[1]) * (p1[0] - p3[0])) / denominator
    ub = ((p2[0] - p1[0]) * (p1[1] - p3[1]) - (p2[1] - p1[1]) * (p1[0] - p3[0])) / denominator
    return if ub.negative? || ub > 1

    [ p1[0] + ua * (p2[0] - p1[0]), p1[1] + ua * (p2[1] - p1[1]) ]
  end

  def distance(p1, p2)
    Math.sqrt((p1[0] - p2[0])**2 + (p1[1] - p2[1])**2)
  end
end
