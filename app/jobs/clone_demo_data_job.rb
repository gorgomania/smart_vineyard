class CloneDemoDataJob < ApplicationJob
  queue_as :default

  # Наполняет демо после входа: ряды, кусты, файлы. У мастера это сотни тысяч записей, поэтому всё копирует
  # сама база (INSERT … SELECT): через Ruby файлы копировались в разы дольше.
  # Карты — старый id → новый, из DemoCloneService. Всё в одной транзакции: повтор после сбоя начнёт с чистого листа
  def perform(_user_id, folder_map, vineyard_map: {})
    folders = id_arrays(folder_map)
    vineyards = id_arrays(vineyard_map)

    ActiveRecord::Base.transaction do
      copy_rows_and_bushes(vineyards) if vineyard_map.any?
      copy_media_items(folders, vineyards)
    end

    # Пользователь уже внутри: открытые карта, статистика и папки подтягивают появившиеся данные
    Vineyard.broadcast_diagnoses_changed(vineyard_map.values)
    Folder.where(id: folder_map.values).find_each(&:broadcast_new_files)
  end

  private

  def id_arrays(map)
    [ map.keys.map(&:to_i), map.values.map(&:to_i) ]
  end

  # m — таблица «старый виноградник → новый» из двух массивов id (параметры запроса)
  def copy_rows_and_bushes(vineyards)
    execute_sql(<<~SQL, *vineyards)
      INSERT INTO rows (vineyard_id, row_number, created_at, updated_at)
      SELECT m.new_id, r.row_number, now(), now()
      FROM rows r
      JOIN unnest(ARRAY[?]::bigint[], ARRAY[?]::bigint[]) AS m(old_id, new_id) ON m.old_id = r.vineyard_id
    SQL
    # Новый ряд — по винограднику и номеру (уникальны вместе), куст переносим с номером как есть
    execute_sql(<<~SQL, *vineyards)
      INSERT INTO bushes (row_id, vineyard_id, bush_number, created_at, updated_at)
      SELECT nr.id, m.new_id, b.bush_number, now(), now()
      FROM bushes b
      JOIN rows r ON r.id = b.row_id
      JOIN unnest(ARRAY[?]::bigint[], ARRAY[?]::bigint[]) AS m(old_id, new_id) ON m.old_id = r.vineyard_id
      JOIN rows nr ON nr.vineyard_id = m.new_id AND nr.row_number = r.row_number
    SQL
  end

  # Записи и вложения (оригинал и превью видео) одним запросом. Копии делят блобы с мастером, файлы не копируются.
  # Новые id берём заранее: по ним вложения находят свою копию. Порядок id сохраняет порядок файлов в папке.
  # Куст копии — с теми же номерами ряда и куста в клоне; нет клона (мастер удалил виноградник) — файл без привязки
  def copy_media_items(folders, vineyards)
    execute_sql(<<~SQL, *folders, *vineyards)
      WITH items AS (
        SELECT source.*, nextval(pg_get_serial_sequence('media_items', 'id')) AS new_id
        FROM (
          SELECT i.id, f.new_id AS folder_id, nb.id AS bush_id,
                 i.ai_class_id, i.ai_confidence, i.ai_classified_at, i.ai_full_results
          FROM media_items i
          JOIN unnest(ARRAY[?]::bigint[], ARRAY[?]::bigint[]) AS f(old_id, new_id) ON f.old_id = i.folder_id
          LEFT JOIN bushes b ON b.id = i.bush_id
          LEFT JOIN rows r ON r.id = b.row_id
          LEFT JOIN unnest(ARRAY[?]::bigint[], ARRAY[?]::bigint[]) AS m(old_id, new_id) ON m.old_id = b.vineyard_id
          LEFT JOIN rows nr ON nr.vineyard_id = m.new_id AND nr.row_number = r.row_number
          LEFT JOIN bushes nb ON nb.row_id = nr.id AND nb.bush_number = b.bush_number
          ORDER BY i.id
        ) source
      ), inserted AS (
        INSERT INTO media_items (id, folder_id, bush_id, ai_class_id, ai_confidence, ai_classified_at, ai_full_results, created_at, updated_at)
        SELECT new_id, folder_id, bush_id, ai_class_id, ai_confidence, ai_classified_at, ai_full_results, now(), now()
        FROM items
      )
      INSERT INTO active_storage_attachments (name, record_type, record_id, blob_id, created_at)
      SELECT a.name, a.record_type, items.new_id, a.blob_id, now()
      FROM active_storage_attachments a
      JOIN items ON items.id = a.record_id
      WHERE a.record_type = 'MediaItem'
    SQL
  end

  def execute_sql(sql, *binds)
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([ sql, *binds ]))
  end
end
