class CreateMediaItems < ActiveRecord::Migration[8.0]
  def change
    create_table :media_items do |t|
      t.references :folder, foreign_key: { to_table: :folders, on_delete: :cascade }
      t.timestamps
    end
  end
end
