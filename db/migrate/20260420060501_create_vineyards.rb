class CreateVineyards < ActiveRecord::Migration[8.0]
  def up
    enable_extension 'postgis' unless extension_enabled?('postgis')

    create_table :vineyards do |t|
      t.string :name, null: false
      t.geometry :polygon, geographic: true, srid: 4326, type: 'polygon', null: false
      t.string :grape_variety
      t.integer :planting_year
      t.references :user, null: false, foreign_key: { to_table: :users, on_delete: :cascade }

      # Расчётные параметры (сохраняем при создании/обновлении)
      t.decimal :area_hectares, precision: 10, scale: 4  # Площадь в гектарах (точность 4 знака)
      t.integer :total_rows, null: false, default: 0      # Общее количество рядов
      t.integer :total_bushes, null: false, default: 0    # Общее количество кустов

      # Детализация по рядам (храним в JSON)
      t.jsonb :rows_details, null: false, default: '[]'     # Информация о каждом ряде
      
      # Параметры посадки (с какими параметрами был сделан расчёт)
      t.decimal :row_spacing, precision: 5, scale: 2, default: 3.0    # Расстояние между рядами (м)
      t.decimal :bush_spacing, precision: 5, scale: 2, default: 1.5   # Расстояние между кустами (м)

      t.timestamps
    end
    
    add_index :vineyards, [:user_id, :name], unique: true
    add_index :vineyards, :polygon, using: :gist
    add_index :vineyards, :rows_details, using: :gin  # Индекс для JSONB
    
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

    # Проверка: Площадь не превышает 20 га
    execute <<-SQL
      ALTER TABLE vineyards
      ADD CONSTRAINT check_area_limit
      CHECK (area_hectares <= 20 OR area_hectares IS NULL)
    SQL

    # Проверка: Реалистичные значения расстояний
    execute <<-SQL
      ALTER TABLE vineyards
      ADD CONSTRAINT check_row_spacing_range
      CHECK (row_spacing BETWEEN 2.0 AND 3.0)
    SQL
    
    execute <<-SQL
      ALTER TABLE vineyards
      ADD CONSTRAINT check_bush_spacing_range
      CHECK (bush_spacing BETWEEN 1.2 AND 1.8)
    SQL
  end

  def down
    if table_exists?(:vineyards)
      execute "ALTER TABLE vineyards DROP CONSTRAINT IF EXISTS check_polygon_is_rectangle"
      execute "ALTER TABLE vineyards DROP CONSTRAINT IF EXISTS check_area_limit"
      execute "ALTER TABLE vineyards DROP CONSTRAINT IF EXISTS check_row_spacing_range"
      execute "ALTER TABLE vineyards DROP CONSTRAINT IF EXISTS check_bush_spacing_range"
      remove_index :vineyards, [:user_id, :name] if index_exists?(:vineyards, [:user_id, :name])
      remove_index :vineyards, :polygon if index_exists?(:vineyards, :polygon)
      remove_index :vineyards, :rows_details if index_exists?(:vineyards, :rows_details)
      drop_table :vineyards
    end
  end
end