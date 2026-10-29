class Bush < ApplicationRecord
  belongs_to :row
  belongs_to :vineyard
  has_one :media_item, dependent: :nullify

  validates :bush_number, presence: true, uniqueness: { scope: :row_id }

  INSERT_BATCH_SIZE = 5_000

  # Массовая вставка кустов: { row_id => (1..40) } — пачками по INSERT_BATCH_SIZE вместо create! на каждый куст.
  # Валидации и колбэки не вызываются: номера в диапазонах должны быть свободны
  def self.insert_numbered!(vineyard_id, numbers_by_row_id)
    now = Time.current
    rows = numbers_by_row_id.flat_map do |row_id, numbers|
      numbers.map { |n| { row_id:, vineyard_id:, bush_number: n, created_at: now, updated_at: now } }
    end
    rows.each_slice(INSERT_BATCH_SIZE) { |batch| insert_all!(batch) }
  end

  def display_name
    "Куст #{bush_number}"
  end
end
