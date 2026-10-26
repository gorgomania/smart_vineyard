class AddSearchIndexesToFoldersAndBlobs < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"

    add_index :folders, :title, using: :gin, opclass: :gin_trgm_ops
    add_index :active_storage_blobs, :filename, using: :gin, opclass: :gin_trgm_ops
  end
end
