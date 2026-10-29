class MakeBushAndVineyardLinksUnique < ActiveRecord::Migration[8.1]
  def up
    # Без очистки создание уникального индекса упадёт на уже существующих дублях.
    # Оставляем самую раннюю привязку (меньший id), у остальных снимаем её
    execute <<~SQL
      UPDATE media_items SET bush_id = NULL
      WHERE id IN (
        SELECT id FROM (
          SELECT id, ROW_NUMBER() OVER (PARTITION BY bush_id ORDER BY id) AS rn
          FROM media_items WHERE bush_id IS NOT NULL
        ) ranked WHERE rn > 1
      )
    SQL

    execute <<~SQL
      UPDATE folders SET vineyard_id = NULL
      WHERE id IN (
        SELECT id FROM (
          SELECT id, ROW_NUMBER() OVER (PARTITION BY vineyard_id ORDER BY id) AS rn
          FROM folders WHERE vineyard_id IS NOT NULL
        ) ranked WHERE rn > 1
      )
    SQL

    remove_index :media_items, :bush_id
    add_index :media_items, :bush_id, unique: true

    remove_index :folders, :vineyard_id
    add_index :folders, :vineyard_id, unique: true
  end

  def down
    remove_index :media_items, :bush_id
    add_index :media_items, :bush_id

    remove_index :folders, :vineyard_id
    add_index :folders, :vineyard_id
  end
end
