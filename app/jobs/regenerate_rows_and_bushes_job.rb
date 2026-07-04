class RegenerateRowsAndBushesJob < ApplicationJob
  queue_as :default

  def perform(vineyard_id, new_bushes_per_row)
    vineyard = Vineyard.find(vineyard_id)
    bushes_per_row = vineyard.rows
                         .left_joins(:bushes)
                         .group(:id, :row_number)
                         .order(:row_number)
                         .pluck(:row_number, "COUNT(bushes.id)")
                         .map(&:last)

    # Если это строка - парсим JSON
    if new_bushes_per_row.is_a?(String)
      new_bushes_per_row = JSON.parse(new_bushes_per_row).map(&:to_i)
    end

    max_length = [ new_bushes_per_row.length, bushes_per_row.length ].max
    a1 = new_bushes_per_row + [ 0 ] * (max_length - new_bushes_per_row.length)
    a2 = bushes_per_row + [ 0 ] * (max_length - bushes_per_row.length)
    result = a1.zip(a2).map { |a, b| a - b }

    ActiveRecord::Base.transaction do
      result.each_with_index do |bushes_count, row_index|
        row_number = row_index + 1
        if a1[row_index] == 0
          # Удаляем ряд
          vineyard.rows.where(row_number: row_number).destroy_all
        elsif a2[row_index] == 0
          # Создаём ряд
          row = vineyard.rows.create!(row_number: row_number)

          # Создаём кусты
          bushes_count.to_i.times do |bush_index|
            bush_number = bush_index + 1
            bush_attrs = {
              vineyard: vineyard,
              bush_number: bush_number
            }
            row.bushes.create!(bush_attrs)
          end
        else
          if bushes_count < 0
            vineyard.rows.where(row_number: row_number).first.bushes.where("bush_number > ?", new_bushes_per_row[row_index]).destroy_all
          else
            row = vineyard.rows.find_by(row_number: row_number)
            # Создаём кусты
            bushes_count.to_i.times do |bush_index|
              bush_number = bush_index + bushes_per_row[row_index] + 1
              bush_attrs = {
                vineyard: vineyard,
                bush_number: bush_number
              }
              row.bushes.create!(bush_attrs)
            end
          end
        end
      end
    end

    if vineyard.folder.present?
      DistributeFolderToBushesJob.perform_later(vineyard.folder.id)
    end
  end
end
