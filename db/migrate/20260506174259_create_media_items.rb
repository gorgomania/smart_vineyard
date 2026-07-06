class CreateMediaItems < ActiveRecord::Migration[8.0]
  def change
    create_table :media_items do |t|
      t.references :folder, foreign_key: { on_delete: :cascade }, null: false
      t.references :bush, foreign_key: { on_delete: :nullify }

      # AI classification fields
      t.integer :ai_class_id
      t.float :ai_confidence
      t.datetime :ai_classified_at
      t.jsonb :ai_full_results, default: {}

      t.timestamps
    end
    # Add indexes for classification search
    add_index :media_items, :ai_class_id
  end
end
