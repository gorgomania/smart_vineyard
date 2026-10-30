class Row < ApplicationRecord
  belongs_to :vineyard
  has_many :bushes, dependent: :destroy

  validates :row_number, presence: true, uniqueness: { scope: :vineyard_id }

  # Ряды, в которых есть свободные кусты: [[ряд, число свободных кустов], ...]
  def self.with_free_bushes(vineyard, keep_bush_id: nil)
    counts = Bush.free(keep_bush_id:).where(vineyard:).group(:row_id).count
    vineyard.rows.where(id: counts.keys).order(:row_number).map { |row| [ row, counts[row.id] ] }
  end

  def free_bushes_label(count)
    "Ряд #{row_number} (#{count} #{Russian.p(count, 'свободный куст', 'свободных куста', 'свободных кустов')})"
  end
end
