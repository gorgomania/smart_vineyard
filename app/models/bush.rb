class Bush < ApplicationRecord
  belongs_to :row
  belongs_to :vineyard
  has_one :media_item, dependent: :nullify

  validates :bush_number, presence: true, uniqueness: { scope: :row_id }

  # Кусты без файла. keep_bush_id — текущий куст перекрепляемого файла: его тоже можно выбрать
  scope :free, ->(keep_bush_id: nil) {
    where.not(id: MediaItem.where.not(bush_id: [ nil, keep_bush_id ]).select(:bush_id))
  }

  # Массовая вставка кустов: { row_id => (1..40) } — один INSERT … SELECT, номера разворачивает сама база
  # (generate_series). Строить в Ruby хэш на каждый куст для insert_all! — ~140 мкс на куст:
  # 50 га (209 тысяч кустов) вставлялись 29 с, так — 4 с.
  # Валидации и колбэки не вызываются: номера в диапазонах должны быть свободны
  def self.insert_numbered!(vineyard_id, numbers_by_row_id)
    return if numbers_by_row_id.empty?

    now = Time.current
    row_ids, firsts, lasts = numbers_by_row_id.map { |row_id, numbers| [ row_id, numbers.first, numbers.last ] }.transpose
    connection.execute(sanitize_sql_array([ <<~SQL, vineyard_id, now, now, row_ids, firsts, lasts ]))
      INSERT INTO #{quoted_table_name} (row_id, vineyard_id, bush_number, created_at, updated_at)
      SELECT r.row_id, ?, n, ?, ?
      FROM unnest(ARRAY[?]::bigint[], ARRAY[?]::integer[], ARRAY[?]::integer[]) AS r(row_id, first_number, last_number)
      CROSS JOIN LATERAL generate_series(r.first_number, r.last_number) AS n
    SQL
  end

  def display_name
    "Куст #{bush_number}"
  end
end
