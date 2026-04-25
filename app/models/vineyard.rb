class Vineyard < ApplicationRecord
  belongs_to :user
  
  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :user_id }
  validates :polygon, presence: true
  validates :area_hectares, numericality: { greater_than: 0, less_than_or_equal_to: 20 }
  validates :grape_variety, length: { maximum: 50 }, allow_blank: true
  validates :planting_year, 
            numericality: { 
              only_integer: true, 
              greater_than_or_equal_to: 1900,
              less_than_or_equal_to: Date.current.year,
              allow_nil: true 
            }
  validates :total_rows, numericality: { greater_than: 0 }
  validates :total_bushes, numericality: { greater_than: 0 }
  validates :row_spacing, numericality: { greater_than_or_equal_to: 2.0, less_than_or_equal_to: 3.0 }
  validates :bush_spacing, numericality: { greater_than_or_equal_to: 1.2, less_than_or_equal_to: 1.8 }

  # Сериализация JSONB
  serialize :bushes_per_row, type: Array, coder: JSON
  
  validate :coordinates_in_range
  
  private
  
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
end