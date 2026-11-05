# На участках с выемкой («Г», «П») ряды обрывались: раскладка останавливалась на первой линии, которая
# пересекала границу не ровно дважды, а у таких участков линию разрывает выемка. Расчёт исправлен
# (app/javascript/utils/vineyard_rows.js и VineyardLayout): разорванная линия — один ряд из нескольких кусков.
# Пересчитываем только виноградники, у которых раскладка в базе не совпадает с новой, — выпуклых это не касается.
# Ряды и кусты подгоняет SyncRowsAndBushesJob, как и в RelayoutVineyardRows
class RelayoutConcaveVineyards < ActiveRecord::Migration[8.0]
  def up
    Vineyard.where(deleted_at: nil).find_each do |vineyard|
      bushes_per_row = VineyardLayout.for(vineyard).bushes_per_row
      next if bushes_per_row.none?(&:positive?)

      expected = bushes_per_row.each_with_index.to_h { |count, i| [ i + 1, count ] }
      current = Bush.where(vineyard_id: vineyard.id).joins(:row).group("rows.row_number").count
      next if current == expected

      vineyard.update_columns(total_rows: bushes_per_row.size, total_bushes: bushes_per_row.sum)
      SyncRowsAndBushesJob.perform_later(vineyard.id, bushes_per_row)
    end
  end

  def down; end
end
