class CreateBushes < ActiveRecord::Migration[8.0]
  def change
    create_table :bushes do |t|
      t.references :row, foreign_key: true, null: false
      t.references :vineyard, foreign_key: true, null: false
      t.integer :bush_number, null: false
      t.timestamps

      t.index [ :row_id, :bush_number ], unique: true
      t.index [ :vineyard_id, :bush_number ]
    end
  end
end
