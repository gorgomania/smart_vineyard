class DistributeMediaToBushesJob < ApplicationJob
  queue_as :default

  def perform(media_item_ids)
    media_items = MediaItem.where(id: media_item_ids)
    return if media_items.empty?

    # Берём папку из первого медиа
    folder = media_items.first.folder
    vineyard = folder.vineyard

    return unless vineyard

    bushes_by_coords = vineyard.bushes.joins(:row)
      .select("bushes.*, rows.row_number AS row_number")
      .each_with_object({}) { |b, h| h[[ b.row_number.to_i, b.bush_number ]] = b }

    media_items.find_each do |media|
      filename = media.media.filename.to_s
      match = filename.match(/(?:Ряд|ряд)\s*(\d+)\s*(?:Куст|куст)\s*(\d+)/)
      next unless match

      bush = bushes_by_coords[[ match[1].to_i, match[2].to_i ]]
      media.update(bush: bush) if bush
    end
  end
end
