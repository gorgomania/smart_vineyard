# Файлы в папке листаются страницами по (created_at, id): у пачек из ZIP и демо-копий created_at общий,
# и без id порядок одинаковых строк не определён — файл мог попасть на две страницы, а другой ни на одну.
# Индекс в том же порядке отдаёт страницу прямо из себя, без сортировки всей папки на диске.
# CONCURRENTLY — запись в media_items не блокируется, пока индекс строится
class AddIdToMediaItemsFolderOrderIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :media_items, [ :folder_id, :created_at, :id ], algorithm: :concurrently
    remove_index :media_items, [ :folder_id, :created_at ], algorithm: :concurrently
  end
end
