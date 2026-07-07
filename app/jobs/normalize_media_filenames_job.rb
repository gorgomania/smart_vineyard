class NormalizeMediaFilenamesJob < ApplicationJob
  queue_as :low_priority

  def perform(media_item_ids)
    media_items = MediaItem.where(id: media_item_ids)

    media_items.find_each do |media_item|
      media_item.media.blob.save if media_item.normalize_filename!
    end
  end
end
