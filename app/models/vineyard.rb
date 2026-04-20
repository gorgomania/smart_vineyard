class Vineyard < ApplicationRecord
  belongs_to :user
  
  validates :name, presence: true, length: { maximum: 100 }
  validates :north_lat, :south_lat, :east_lng, :west_lng, presence: true
  validates :grape_variety, length: { maximum: 50 }, allow_blank: true
  validates :planting_year, 
            numericality: { 
              only_integer: true, 
              greater_than_or_equal_to: 1900,
              less_than_or_equal_to: Date.current.year,
              allow_nil: true 
            }
  
  before_validation :normalize_coordinates
  validate :coordinates_valid
  
  private
  
  def normalize_coordinates
    # Меняем местами север и юг
    if north_lat && south_lat && north_lat <= south_lat
      self.north_lat, self.south_lat = south_lat, north_lat
    end
    
    # Меняем местами восток и запад
    if east_lng && west_lng && east_lng <= west_lng
      self.east_lng, self.west_lng = west_lng, east_lng
    end
  end

  def coordinates_valid
    if north_lat <= south_lat
      errors.add(:base, "Северная широта должна быть больше южной")
    end
    
    if east_lng <= west_lng
      errors.add(:base, "Восточная долгота должна быть больше западной")
    end
    
    if north_lat > 90 || north_lat < -90
      errors.add(:north_lat, "должна быть в диапазоне от -90 до 90")
    end
    
    if south_lat > 90 || south_lat < -90
      errors.add(:south_lat, "должна быть в диапазоне от -90 до 90")
    end
    
    if east_lng > 180 || east_lng < -180
      errors.add(:east_lng, "должна быть в диапазоне от -180 до 180")
    end
    
    if west_lng > 180 || west_lng < -180
      errors.add(:west_lng, "должна быть в диапазоне от -180 до 180")
    end
  end
end