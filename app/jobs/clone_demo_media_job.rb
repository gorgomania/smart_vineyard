class CloneDemoMediaJob < ApplicationJob
  queue_as :default

  # vineyard_map — старый виноградник → новый: по нему находим кусты демо для привязанных файлов
  def perform(user_id, folder_map, vineyard_map: {})
    folder_map = folder_map.transform_keys(&:to_i)
    now = Time.current

    items = MediaItem
      .where(folder_id: folder_map.keys)
      .includes(media_attachment: :blob, video_preview_attachment: :blob)
      .order(:id)
      .to_a

    return if items.empty?

    bush_map = demo_bush_map(items.filter_map(&:bush_id).uniq, vineyard_map)

    items_data = items.map do |item|
      {
        folder_id:        folder_map[item.folder_id],
        bush_id:          bush_map[item.bush_id],
        ai_class_id:      item.ai_class_id,
        ai_confidence:    item.ai_confidence,
        ai_classified_at: item.ai_classified_at,
        ai_full_results:  item.ai_full_results,
        created_at:       now,
        updated_at:       now
      }
    end

    # Записи и их файлы — вместе или никак: при сбое между вставками остались бы пустые карточки
    ActiveRecord::Base.transaction do
      new_ids = MediaItem.insert_all!(items_data, returning: [ :id ]).map { |r| r["id"] }
      attach_blobs(items, new_ids, now)
    end
  end

  private

  # Старый куст → куст демо с тем же номером ряда и куста в клоне виноградника. Нет пары (виноградник
  # мастер удалил, куста в клоне нет) — файл в демо остаётся без привязки
  def demo_bush_map(bush_ids, vineyard_map)
    return {} if bush_ids.empty? || vineyard_map.empty?

    old_ids = vineyard_map.keys.map(&:to_i)
    new_ids = vineyard_map.values.map(&:to_i)
    sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL, old_ids, new_ids, bush_ids ])
      SELECT b.id, nb.id
      FROM bushes b
      JOIN rows r ON r.id = b.row_id
      JOIN unnest(ARRAY[?]::bigint[], ARRAY[?]::bigint[]) AS m(old_id, new_id) ON m.old_id = b.vineyard_id
      JOIN rows nr ON nr.vineyard_id = m.new_id AND nr.row_number = r.row_number
      JOIN bushes nb ON nb.row_id = nr.id AND nb.bush_number = b.bush_number
      WHERE b.id IN (?)
    SQL
    ActiveRecord::Base.connection.select_rows(sql).to_h { |old_id, new_id| [ old_id.to_i, new_id.to_i ] }
  end

  def attach_blobs(items, new_ids, now)
    media_attachments = items.each_with_index.filter_map do |item, i|
      next unless item.media.attached?
      { name: "media", record_type: "MediaItem", record_id: new_ids[i], blob_id: item.media_attachment.blob_id, created_at: now }
    end
    ActiveStorage::Attachment.insert_all!(media_attachments) if media_attachments.any?

    preview_attachments = items.each_with_index.filter_map do |item, i|
      next unless item.video_preview.attached?
      { name: "video_preview", record_type: "MediaItem", record_id: new_ids[i], blob_id: item.video_preview_attachment.blob_id, created_at: now }
    end
    ActiveStorage::Attachment.insert_all!(preview_attachments) if preview_attachments.any?
  end
end
