class CreateVineyards < ActiveRecord::Migration[8.0]
  def up
    enable_extension 'postgis' unless extension_enabled?('postgis')

    create_table :vineyards do |t|
      t.string :name, null: false
      t.geometry :polygon, geographic: true, srid: 4326, type: 'polygon', null: false
      t.string :grape_variety
      t.integer :planting_year
      t.references :user, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.timestamps
    end
    
    add_index :vineyards, [:user_id, :name], unique: true
    add_index :vineyards, :polygon, using: :gist
    
    # Проверка 1: Прямоугольник (4 точки)
    execute <<-SQL
      ALTER TABLE vineyards
      ADD CONSTRAINT check_polygon_is_rectangle
      CHECK (
        ST_NumPoints(ST_ExteriorRing(polygon::geometry)) = 5
        AND ST_IsClosed(ST_ExteriorRing(polygon::geometry))
        AND ST_IsValid(polygon::geometry)
      )
    SQL
  end

  def down
    if table_exists?(:vineyards)
      execute "ALTER TABLE vineyards DROP CONSTRAINT IF EXISTS check_polygon_is_rectangle"
      remove_index :vineyards, [:user_id, :name] if index_exists?(:vineyards, [:user_id, :name])
      remove_index :vineyards, :polygon if index_exists?(:vineyards, :polygon)
      drop_table :vineyards
    end
  end
end