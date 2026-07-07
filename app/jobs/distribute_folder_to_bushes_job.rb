# app/jobs/distribute_media_job.rb
class DistributeFolderToBushesJob < ApplicationJob
  queue_as :default

  def perform(folder_id)
    folder = Folder.find_by(id: folder_id)
    return unless folder

    vineyard = folder.vineyard
    media_items = folder.media_items

    bushes_by_coords = vineyard&.bushes&.joins(:row)
      &.select("bushes.*, rows.row_number AS row_number")
      &.each_with_object({}) { |b, h| h[[ b.row_number.to_i, b.bush_number ]] = b }

    media_items.find_each do |media|
      filename = media.media.filename.to_s

      # Только формат: Ряд 1 Куст 1
      match = filename.match(/(?:Ряд|ряд)\s*(\d+)\s*(?:Куст|куст)\s*(\d+)/)
      next unless match

      if vineyard.present?
        bush = bushes_by_coords[[ match[1].to_i, match[2].to_i ]]
        media.update(bush: bush) if bush
      else
        media.update(bush: nil)
      end
    end
  end
end
