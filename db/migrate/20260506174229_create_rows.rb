class CreateRows < ActiveRecord::Migration[8.0]
  def change
    create_table :rows do |t|
      t.references :vineyard, foreign_key: { on_delete: :cascade }, null: false
      t.integer :row_number, null: false
      t.timestamps

      t.index [ :vineyard_id, :row_number ], unique: true
    end
  end
end
