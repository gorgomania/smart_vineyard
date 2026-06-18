class GenerateRowsAndBushesJob < ApplicationJob
  queue_as :default

  def perform(vineyard_id, bushes_per_row_data)
    vineyard = Vineyard.find(vineyard_id)
    bushes_per_row = bushes_per_row_data

    # Если это строка - парсим JSON
    if bushes_per_row.is_a?(String)
      bushes_per_row = JSON.parse(bushes_per_row)
    end

    ActiveRecord::Base.transaction do
      bushes_per_row.each_with_index do |bushes_count, row_index|
        row_number = row_index + 1

        # Создаём ряд
        row = vineyard.rows.create!(row_number: row_number)

        # Создаём кусты в ряду
        bushes_count.to_i.times do |bush_index|
          bush_number = bush_index + 1
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
