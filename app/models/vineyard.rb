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
  validate :bushes_per_row_must_match_totals
  
  private
  def bushes_per_row_must_match_totals
    return if bushes_per_row.blank? || total_rows.blank?
    
    # Проверка длины
    if bushes_per_row.length != total_rows
      errors.add(:bushes_per_row, 
        "должен содержать #{total_rows} рядов, получено #{bushes_per_row.length}")
    end
    
    # Проверка суммы
    if total_bushes.present? && bushes_per_row.sum != total_bushes
      errors.add(:bushes_per_row, 
        "сумма кустов по рядам (#{bushes_per_row.sum}) не равна total_bushes (#{total_bushes})")
    end
  end
end