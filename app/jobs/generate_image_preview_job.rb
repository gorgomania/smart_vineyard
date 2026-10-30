class GenerateImagePreviewJob < ApplicationJob
  queue_as :heavy
  queue_with_priority PREVIEW_PRIORITY
  discard_on ActiveRecord::RecordNotFound

  def perform(media_item_id)
    item = MediaItem.find(media_item_id)
    item.media.variant(resize_to_limit: [ 132, 88 ]).processed
  end
end
