class RegenerateRowsAndBushesJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(vineyard_id, new_bushes_per_row)
    vineyard = Vineyard.find(vineyard_id)

    # Если это строка - парсим JSON
    if new_bushes_per_row.is_a?(String)
      new_bushes_per_row = JSON.parse(new_bushes_per_row)
    end
    new_bushes_per_row = new_bushes_per_row.map(&:to_i)

    # Пустая раскладка означает, что карта ничего не посчитала, а не «удалить все ряды»
    return if new_bushes_per_row.blank? || new_bushes_per_row.none?(&:positive?)

    # row_number => [row_id, max bush_number]; max, а не count — чтобы новые номера не пересеклись при дырах
    current_rows = vineyard.rows
                           .left_joins(:bushes)
                           .group(:id, :row_number)
                           .pluck(:row_number, :id, "MAX(bushes.bush_number)")
                           .to_h { |number, id, max| [ number, [ id, max.to_i ] ] }
    target_count = ->(row_number) { new_bushes_per_row[row_number - 1].to_i }

    now = Time.current
    ActiveRecord::Base.transaction do
      # Ряды, которых больше нет (или с 0 кустов): delete_all одним SQL,
      # кусты удалит FK on_delete: :cascade, привязки media_items обнулит on_delete: :nullify
      removed_row_ids = current_rows.filter_map { |number, (id, _)| id if target_count.(number).zero? }
      Row.where(id: removed_row_ids).delete_all if removed_row_ids.any?

      new_bushes = {}

      current_rows.each do |number, (id, max)|
        target = target_count.(number)
        next if target.zero?

        if target < max
          Bush.where(row_id: id).where("bush_number > ?", target).delete_all
        elsif target > max
          new_bushes[id] = (max + 1)..target
        end
      end

      new_rows_data = new_bushes_per_row.each_with_index.filter_map do |count, row_index|
        row_number = row_index + 1
        next if count.zero? || current_rows.key?(row_number)

        { vineyard_id: vineyard.id, row_number:, created_at: now, updated_at: now }
      end

      if new_rows_data.any?
        Row.insert_all!(new_rows_data, returning: [ :id, :row_number ]).each do |r|
          new_bushes[r["id"]] = 1..target_count.(r["row_number"])
        end
      end

      Bush.insert_numbered!(vineyard.id, new_bushes)
    end

    if vineyard.folder.present?
      DistributeMediaToBushesJob.perform_later(vineyard.folder.id)
    end
  end
end
