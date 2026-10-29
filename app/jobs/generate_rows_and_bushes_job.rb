class GenerateRowsAndBushesJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(vineyard_id, bushes_per_row_data)
    vineyard = Vineyard.find(vineyard_id)
    bushes_per_row = bushes_per_row_data

    # Если это строка - парсим JSON
    if bushes_per_row.is_a?(String)
      bushes_per_row = JSON.parse(bushes_per_row)
    end
    bushes_per_row = bushes_per_row.map(&:to_i)
    return if bushes_per_row.empty?

    now = Time.current
    ActiveRecord::Base.transaction do
      # Все ряды одним INSERT, кусты — пачками: на 10 га это десятки тысяч записей
      rows_data = bushes_per_row.each_index.map do |row_index|
        { vineyard_id: vineyard.id, row_number: row_index + 1, created_at: now, updated_at: now }
      end
      row_ids = Row.insert_all!(rows_data, returning: [ :id, :row_number ])
                   .to_h { |r| [ r["row_number"], r["id"] ] }

      Bush.insert_numbered!(
        vineyard.id,
        bushes_per_row.each_with_index.to_h { |count, row_index| [ row_ids[row_index + 1], 1..count ] }
      )
    end
  end
end
