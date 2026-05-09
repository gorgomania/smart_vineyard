class Vineyard < ApplicationRecord
  belongs_to :user
  has_many :rows, dependent: :destroy
  has_many :bushes, through: :rows
  has_many :media_items, through: :bushes

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :user_id }
  validates :polygon, presence: true
  validates :area_hectares, numericality: { greater_than: 0, less_than_or_equal_to: 10 }
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

  scope :for_index, -> {
    select(:id, :name, :polygon, :area_hectares, :grape_variety, :total_rows, :total_bushes)
  }

  def bushes_diagnoses
    bushes.left_joins(:media_item)
          .order("rows.row_number ASC, bushes.bush_number ASC")
          .pluck("media_items.ai_class_id")
  end

  def area_hectares=(value)
    if value.is_a?(String)
      # Удаляем последние 3 символа если это ' га' или просто 'га'
      cleaned = value.gsub(/\s*га$/, "")  # Удаляет ' га' или 'га' в конце
      value = cleaned.to_f
    end
    super(value)
  end
end
