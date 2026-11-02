# Предел площади 10 га появился из-за отрисовки: каждая точка тепловой карты была меткой Яндекс Карт, и 41 тысяча
# кустов рисовалась ~20 с. Теперь кусты рисует свой canvas-слой (app/javascript/utils/heatmap_layer.js),
# кусты вставляются одним INSERT (Bush.insert_numbered!) — предел 50 га, как Vineyard::MAX_AREA_HECTARES
class RaiseVineyardAreaLimit < ActiveRecord::Migration[8.0]
  def up
    replace_area_limit(50)
  end

  # Откат не пройдёт, если уже есть виноградники больше 10 га
  def down
    replace_area_limit(10)
  end

  private

  def replace_area_limit(hectares)
    execute <<~SQL
      ALTER TABLE vineyards DROP CONSTRAINT check_area_limit;
      ALTER TABLE vineyards ADD CONSTRAINT check_area_limit CHECK (area_hectares <= #{hectares} OR area_hectares IS NULL);
    SQL
  end
end
