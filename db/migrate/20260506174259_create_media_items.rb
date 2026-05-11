class CreateMediaItems < ActiveRecord::Migration[8.0]
  def change
    create_table :media_items do |t|
      t.references :folder, foreign_key: { on_delete: :cascade }
      t.references :bush, foreign_key: true
      # AI classification fields
      t.string :ai_classification
      t.float :ai_confidence
      t.integer :ai_class_id
      t.datetime :ai_classified_at
      t.jsonb :ai_full_results, default: {}
      t.timestamps
    end
    # Add indexes for classification search
    add_index :media_items, :ai_classification
    add_index :media_items, :ai_classified_at
  end
end
