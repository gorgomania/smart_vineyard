class Row < ApplicationRecord
  belongs_to :vineyard
  has_many :bushes, dependent: :destroy

  validates :row_number, presence: true, uniqueness: { scope: :vineyard_id }

  def display_name
    "Ряд #{row_number} (#{bushes.size} #{Russian.p(bushes.size, 'куст', 'куста', 'кустов')})"
  end
end
