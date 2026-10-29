class DistributeMediaToBushesJob < ApplicationJob
  queue_as :default

  def perform(media_item_ids)
    media_items = MediaItem.where(id: media_item_ids)
      .includes(media_attachment: :blob)
      .to_a
    return if media_items.empty?

    folder = media_items.first.folder
    vineyard = folder.vineyard
    return unless vineyard

    bushes_by_coords = vineyard.bushes.joins(:row)
      .select("bushes.*, rows.row_number AS row_number")
      .each_with_object({}) { |b, h| h[[ b.row_number.to_i, b.bush_number ]] = b }

    item_to_bush = {}
    media_items.each do |media|
      filename = media.media_attachment&.blob&.filename.to_s
      next if filename.blank?

      match = filename.match(/(?:Ряд|ряд)\s*(\d+)\s*(?:Куст|куст)\s*(\d+)/)
      next unless match

      bush = bushes_by_coords[[ match[1].to_i, match[2].to_i ]]
      item_to_bush[media.id] = bush.id if bush
    end
    return if item_to_bush.empty?

    occupied_bush_ids = MediaItem
      .where(bush_id: item_to_bush.values)
      .where.not(id: item_to_bush.keys)
      .pluck(:bush_id)
      .to_set

    bush_updates = item_to_bush.reject { |_, bush_id| occupied_bush_ids.include?(bush_id) }
    return if bush_updates.empty?

    when_clauses = bush_updates.map { |mid, bid| "WHEN #{Integer(mid)} THEN #{Integer(bid)}" }.join(" ")
    MediaItem.where(id: bush_updates.keys)
             .update_all([ "bush_id = CASE id #{when_clauses} END, updated_at = ?", Time.current ])
  end
end
