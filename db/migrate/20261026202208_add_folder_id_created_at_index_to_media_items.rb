class AddFolderIdCreatedAtIndexToMediaItems < ActiveRecord::Migration[8.1]
  def change
    add_index :media_items, [ :folder_id, :created_at ]
  end
end
