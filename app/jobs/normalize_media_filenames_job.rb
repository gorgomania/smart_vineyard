class NormalizeMediaFilenamesJob < ApplicationJob
  queue_as :default

  def perform(media_item_ids)
    media_items = MediaItem.where(id: media_item_ids)

    media_items.find_each do |media_item|
      if media_item.normalize_filename!
        media_item.media.blob.save
      end
    end
  end
end
