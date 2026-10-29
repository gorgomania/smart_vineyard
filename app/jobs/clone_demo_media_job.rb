class CloneDemoMediaJob < ApplicationJob
  queue_as :default

  def perform(user_id, folder_map, bush_map)
    folder_map = folder_map.transform_keys(&:to_i)
    bush_map   = bush_map.transform_keys(&:to_i)
    now = Time.current

    items = MediaItem
      .where(folder_id: folder_map.keys)
      .includes(media_attachment: :blob, video_preview_attachment: :blob)
      .order(:id)
      .to_a

    return if items.empty?

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

    new_ids = MediaItem.insert_all!(items_data, returning: [ :id ]).map { |r| r["id"] }

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
