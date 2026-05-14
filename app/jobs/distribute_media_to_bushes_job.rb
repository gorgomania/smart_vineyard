class DistributeMediaToBushesJob < ApplicationJob
  queue_as :default

  def perform(media_item_ids)
    media_items = MediaItem.where(id: media_item_ids)
    return if media_items.empty?

    # Берём папку из первого медиа
    folder = media_items.first.folder
    vineyard = folder.vineyard

    return unless vineyard

    media_items.find_each do |media|
      filename = media.media.filename.to_s
      match = filename.match(/(?:Ряд|ряд)\s*(\d+)\s*(?:Куст|куст)\s*(\d+)/)
      next unless match

      row_number = match[1].to_i
      bush_number = match[2].to_i

      bush = vineyard.bushes
        .joins(:row)
        .where(rows: { row_number: row_number })
        .find_by(bush_number: bush_number)

      if bush
        media.update(bush: bush)
      end
    end
  end
end
