class CreateVineyards < ActiveRecord::Migration[8.0]
  def change
    create_table :vineyards do |t|
      t.string :name, null: false
      t.decimal :north_lat, precision: 10, scale: 7, null: false
      t.decimal :south_lat, precision: 10, scale: 7, null: false
      t.decimal :east_lng, precision: 10, scale: 7, null: false
      t.decimal :west_lng, precision: 10, scale: 7, null: false
      t.string :grape_variety
      t.integer :planting_year
      t.references :user, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.timestamps
    end
    add_index :vineyards, [:user_id, :name], unique: true
    execute <<-SQL
      ALTER TABLE vineyards
      ADD CONSTRAINT check_coordinates
      CHECK (
        north_lat > south_lat 
        AND east_lng > west_lng
        AND north_lat BETWEEN -90 AND 90
        AND south_lat BETWEEN -90 AND 90
        AND east_lng BETWEEN -180 AND 180
        AND west_lng BETWEEN -180 AND 180
      )
    SQL
  end
end
