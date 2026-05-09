class ClassifyMediaJob < ApplicationJob
  queue_as :default

  def perform(media_item_id)
    media_item = MediaItem.find_by(id: media_item_id)
    return unless media_item&.media&.attached?

    media_item.classify!
  end
end
