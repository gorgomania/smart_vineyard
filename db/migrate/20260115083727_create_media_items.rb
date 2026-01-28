class CreateMediaItems < ActiveRecord::Migration[8.0]
  def change
    create_table :media_items do |t|
      t.references :folder
      t.timestamps
    end
  end
end
