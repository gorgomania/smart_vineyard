class Bush < ApplicationRecord
  belongs_to :row
  belongs_to :vineyard
  has_one :media_item, dependent: :nullify

  validates :bush_number, presence: true, uniqueness: { scope: :row_id }

  def display_name
    "Куст #{bush_number}"
  end
end
