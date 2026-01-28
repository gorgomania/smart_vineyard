class CreateFolders < ActiveRecord::Migration[8.0]
  def change
    create_table :folders do |t|
      t.string :title, null: false, limit: 15
      t.references :parent, foreign_key: { to_table: :folders, on_delete: :cascade }
      t.index [ :title, :parent_id ], unique: true
      t.timestamps
    end
  end
end
