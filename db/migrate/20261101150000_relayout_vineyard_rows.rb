# Ряды стояли не через заданный шаг: JS переводил метры в градусы по среднему градусу широты и долготы,
# и при шаге 3 м ряды вставали через 2.5–3.5 м, смотря куда смотрит опорная сторона. Расчёт исправлен
# (app/javascript/utils/vineyard_rows.js и его серверная копия VineyardLayout) — пересчитываем уже созданные
# виноградники. Ряды и кусты в базе подгоняет RegenerateRowsAndBushesJob (затем он же перепривязывает файлы
# «Ряд N Куст M» папки виноградника), числа в карточке виноградника обновляем здесь
class RelayoutVineyardRows < ActiveRecord::Migration[8.0]
  def up
    Vineyard.where(deleted_at: nil).find_each do |vineyard|
      bushes_per_row = VineyardLayout.for(vineyard).bushes_per_row
      next if bushes_per_row.none?(&:positive?)

      vineyard.update_columns(total_rows: bushes_per_row.size, total_bushes: bushes_per_row.sum)
      RegenerateRowsAndBushesJob.perform_later(vineyard.id, bushes_per_row)
    end
  end

  # Старую раскладку не восстановить, да и незачем: она была неверной
  def down; end
end
