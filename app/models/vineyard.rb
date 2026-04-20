class Vineyard < ApplicationRecord
  belongs_to :user
  
  validates :name, presence: true, length: { maximum: 100 }
  validates :polygon, presence: true
  validates :grape_variety, length: { maximum: 50 }, allow_blank: true
  validates :planting_year, 
            numericality: { 
              only_integer: true, 
              greater_than_or_equal_to: 1900,
              less_than_or_equal_to: Date.current.year,
              allow_nil: true 
            }
  
  validate :polygon_is_valid_rectangle
  validate :coordinates_in_range
  validate :rectangle_not_flipped
  
  # Получение границ прямоугольника
  def bounds
    return nil unless polygon
    
    {
      north_lat: polygon.envelope.max_y,
      south_lat: polygon.envelope.min_y,
      east_lng: polygon.envelope.max_x,
      west_lng: polygon.envelope.min_x
    }
  end
  
  # Установка прямоугольника по границам
  def bounds=(coords)
    north_lat = coords[:north_lat]
    south_lat = coords[:south_lat]
    east_lng = coords[:east_lng]
    west_lng = coords[:west_lng]
    
    self.polygon = "POLYGON((
      #{north_lat} #{west_lng},
      #{north_lat} #{east_lng},
      #{south_lat} #{east_lng},
      #{south_lat} #{west_lng},
      #{north_lat} #{west_lng}
    ))"
  end
  
  # Расчет площади в гектарах
  def area_hectares
    return nil unless polygon
    
    # Конвертируем в метры и вычисляем площадь
    area_sq_meters = polygon.transform(3857).area
    (area_sq_meters / 10000).round(2) # гектары
  end
  
  private
  
  # Валидация: полигон должен быть прямоугольником с 4 точками
  def polygon_is_valid_rectangle
    return unless polygon
    
    begin
      exterior_ring = polygon.exterior_ring
      points_count = exterior_ring.points.size
      
      if points_count != 5
        errors.add(:polygon, "must have exactly 4 corners (found #{points_count - 1})")
      end
      
      unless exterior_ring.is_closed?
        errors.add(:polygon, "must be closed")
      end
      
      unless polygon.valid?
        errors.add(:polygon, "is not valid")
      end
    rescue => e
      errors.add(:polygon, "is not a valid polygon: #{e.message}")
    end
  end
  
  # Валидация: координаты должны быть в допустимых диапазонах
  def coordinates_in_range
    return unless polygon
    
    bounds = self.bounds
    
    if bounds[:north_lat] > 90 || bounds[:south_lat] < -90
      errors.add(:polygon, "latitude must be between -90 and 90")
    end
    
    if bounds[:east_lng] > 180 || bounds[:west_lng] < -180
      errors.add(:polygon, "longitude must be between -180 and 180")
    end
  end
  
  # Валидация: прямоугольник не должен быть перевернут
  def rectangle_not_flipped
    return unless polygon
    
    bounds = self.bounds
    
    if bounds[:north_lat] <= bounds[:south_lat]
      errors.add(:polygon, "north must be greater than south")
    end
    
    if bounds[:east_lng] <= bounds[:west_lng]
      errors.add(:polygon, "east must be greater than west")
    end
  end
end