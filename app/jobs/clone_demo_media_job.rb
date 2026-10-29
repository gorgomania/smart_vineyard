class CloneDemoMediaJob < ApplicationJob
  queue_as :default

  def perform(user_id, folder_map, bush_map)
    # JSON serialization converts integer keys to strings
    folder_map = folder_map.transform_keys(&:to_i)
    bush_map = bush_map.transform_keys(&:to_i)

    MediaItem
      .where(folder_id: folder_map.keys)
      .includes(media_attachment: :blob, video_preview_attachment: :blob)
      .find_each do |item|
        new_item = item.dup
        new_item.folder_id = folder_map[item.folder_id]
        new_item.bush_id = bush_map[item.bush_id] if item.bush_id
        new_item.skip_preview_generation = true
        new_item.save!(validate: false)

        new_item.media.attach(item.media.blob) if item.media.attached?
        new_item.video_preview.attach(item.video_preview.blob) if item.video_preview.attached?
      end
  end
end
