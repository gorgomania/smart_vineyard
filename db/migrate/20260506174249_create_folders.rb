class CreateFolders < ActiveRecord::Migration[8.0]
  def change
    create_table :folders do |t|
      t.string :title, null: false, limit: 15
      t.references :parent, foreign_key: { to_table: :folders, on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :vineyard, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
    add_index :folders, :created_at
    add_index :folders, [ :user_id, :title, :parent_id ], unique: true
    add_index :folders, [ :user_id, :title ],  unique: true,  where: "parent_id IS NULL"
  end
end
