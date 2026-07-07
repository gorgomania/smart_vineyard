class AttachMediaJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(folder, signed_blob_ids)
    vineyard = folder.vineyard

    bushes_by_coords = vineyard&.bushes&.joins(:row)
      &.select("bushes.*, rows.row_number AS row_number")
      &.each_with_object({}) { |b, h| h[[ b.row_number.to_i, b.bush_number ]] = b }

    signed_blob_ids.each do |signed_id|
      blob = ActiveStorage::Blob.find_signed(signed_id)
      next unless blob

      media_item = MediaItem.new(folder_id: folder.id)
      media_item.media.attach(blob)
      media_item.normalize_filename!

      if media_item.save
        if blob.content_type.start_with?("image/")
          ClassifyMediaJob.perform_later(media_item.id)
        end

        if vineyard.present?
          filename = blob.filename.to_s
          match = filename.match(/(?:Ряд|ряд)\s*(\d+)\s*(?:Куст|куст)\s*(\d+)/)

          if match
            bush = bushes_by_coords[[ match[1].to_i, match[2].to_i ]]
            media_item.update(bush: bush) if bush
          end
        end
      end
    end
  end
end
