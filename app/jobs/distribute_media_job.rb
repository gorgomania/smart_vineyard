# app/jobs/distribute_media_job.rb
class DistributeMediaJob < ApplicationJob
  queue_as :default

  def perform(folder_id)
    folder = Folder.find_by(id: folder_id)
    return unless folder

    vineyard = folder.vineyard
    media_items = folder.media_items

    media_items.each do |media|
      filename = media.media.filename.to_s

      # Только формат: Ряд 1 Куст 1
      match = filename.match(/(?:Ряд|ряд)\s*(\d+)\s*(?:Куст|куст)\s*(\d+)/)
      next unless match

      if vineyard.present?
        row_number = match[1].to_i
        bush_number = match[2].to_i

        bush = vineyard.bushes
          .joins(:row)
          .where(rows: { row_number: row_number })
          .find_by(bush_number: bush_number)

        media.update(bush: bush) if bush
      else
        media.update!(bush: nil)
      end
    end
  end
end
