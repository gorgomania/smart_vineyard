require "zip"

class ProcessZipJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  MIME_TYPES = {
    ".jpg"  => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".png"  => "image/png",
    ".webp" => "image/webp",
    ".mp4"  => "video/mp4"
  }.freeze

  def perform(folder, zip_path)
    media_items_data = []
    blob_results = []

    Zip::File.open(zip_path) do |zip_file|
      entries = zip_file.select { |e| e.file? && MIME_TYPES.key?(File.extname(e.name).downcase) }

      entries.each do |entry|
        ext = File.extname(entry.name).downcase

        blob = ActiveStorage::Blob.create_and_upload!(
          io: entry.get_input_stream,
          filename: File.basename(entry.name),
          content_type: MIME_TYPES[ext],
          identify: false
        )
        blob_results << blob
        media_items_data << { folder_id: folder.id, created_at: Time.current, updated_at: Time.current }
      end
    end

    media_item_ids = ActiveRecord::Base.transaction do
      result = MediaItem.insert_all!(media_items_data, returning: [ :id ])
      ids = result.map { |r| r["id"] }

      attachments_data = blob_results.each_with_index.map do |blob, i|
        {
          name: "media",
          record_type: "MediaItem",
          record_id: ids[i],
          blob_id: blob.id,
          created_at: Time.current
        }
      end
      ActiveStorage::Attachment.insert_all!(attachments_data)

      ids
    end

    DistributeMediaToBushesJob.perform_later(media_item_ids)

    jobs = []
    media_item_ids.each_with_index do |media_id, index|
      if blob_results[index].content_type.start_with?("image/")
        jobs << ClassifyMediaJob.new(media_id)
        jobs << GenerateImagePreviewJob.new(media_id)
      elsif blob_results[index].content_type.start_with?("video/")
        jobs << GenerateVideoPreviewJob.new(media_id)
      end
    end
    ActiveJob.perform_all_later(jobs)

    NormalizeMediaFilenamesJob.perform_later(media_item_ids)

  rescue => e
    Rails.logger.error "Ошибка обработки ZIP: #{e.message}"
    Rails.logger.error e.backtrace.first(5)
    blob_results&.each { |b| b.purge rescue nil }
    raise e
  ensure
    File.delete(zip_path) if zip_path && File.exist?(zip_path)
  end
end
