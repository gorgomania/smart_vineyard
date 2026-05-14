class AttachMediaJob < ApplicationJob
  queue_as :default

  def perform(folder_id, signed_blob_ids)
    folder = Folder.find(folder_id)
    vineyard = folder.vineyard

    signed_blob_ids.each do |signed_id|
      blob = ActiveStorage::Blob.find_signed(signed_id)

      media_item = MediaItem.new(folder_id: folder_id)
      media_item.media.attach(blob)
      media_item.normalize_filename!

      if media_item.save
        if blob.content_type.start_with?("image/")
          ClassifyMediaJob.perform_later(media_item.id)
        end

        if vineyard.present?
          # Пробуем определить куст по имени файла
          filename = blob.filename.to_s
          match = filename.match(/(?:Ряд|ряд)\s*(\d+)\s*(?:Куст|куст)\s*(\d+)/)

          if match
            row_number = match[1].to_i
            bush_number = match[2].to_i

            bush = vineyard.bushes
              .joins(:row)
              .where(rows: { row_number: row_number })
              .find_by(bush_number: bush_number)

            media_item.update(bush: bush) if bush
          end
        end
      end
    end
  end
end
