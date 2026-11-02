class GenerateRowsAndBushesJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  # bushes_per_row — число кустов в каждом ряду по порядку номеров (VineyardLayout#bushes_per_row)
  def perform(vineyard_id, bushes_per_row)
    vineyard = Vineyard.find(vineyard_id)
    return if bushes_per_row.empty?

    now = Time.current
    ActiveRecord::Base.transaction do
      # По очереди с RegenerateRowsAndBushesJob того же виноградника (создали и сразу поправили)
      vineyard.lock!

      # Все ряды одним INSERT, кусты — тоже одним (Bush.insert_numbered!): на 50 га это сотни тысяч записей
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

    # Папку могли привязать, пока ряды ещё строились: её раскладка тогда не нашла кустов. Повторяем,
    # как RegenerateRowsAndBushesJob после пересчёта
    DistributeMediaToBushesJob.perform_later(vineyard.folder.id) if vineyard.folder.present?
  end
end
