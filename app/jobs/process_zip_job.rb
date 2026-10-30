require "zip"

class ProcessZipJob < ApplicationJob
  queue_as :heavy
  discard_on ActiveRecord::RecordNotFound

  MIME_TYPES = {
    ".jpg"  => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".png"  => "image/png",
    ".webp" => "image/webp",
    ".mp4"  => "video/mp4"
  }.freeze
  CHUNK_SIZE = 1.megabyte

  def perform(folder, zip_blob)
    media_items_data = []
    blob_results = []

    zip_blob.open do |tempfile|
      Zip::File.open(tempfile.path) do |zip_file|
        entries = zip_file.select { |e| e.file? && MIME_TYPES.key?(File.extname(e.name).downcase) }

        entries.each do |entry|
          blob_results << store_entry(entry, MIME_TYPES[File.extname(entry.name).downcase])
          media_items_data << { folder_id: folder.id, created_at: Time.current, updated_at: Time.current }
        end
      end
    end
    return zip_blob.purge if blob_results.empty? # в архиве нет поддерживаемых файлов

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
    # Файлы сохранены — архив больше не нужен, даже если дальше что-то упадёт
    zip_blob.purge

    DistributeMediaToBushesJob.perform_later(folder.id, media_item_ids)

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

    # Последним: сбой рассылки не должен помешать поставить превью и классификацию
    folder.broadcast_new_files
  rescue => e
    Rails.logger.error "Ошибка обработки ZIP: #{e.message}"
    Rails.logger.error e.backtrace.first(5)
    # Пока записи не сохранены, распакованные файлы — сироты. Архив не трогаем: задачу можно повторить,
    # а иначе его уберёт CleanupOrphanedActiveStorageRecordsJob через сутки
    blob_results.each { |b| b.purge rescue nil } unless media_item_ids
    raise e
  end

  private

  # Распаковываем запись один раз, считая checksum на лету. create_and_upload! с потоком из архива
  # распаковывал бы её дважды: для checksum и для записи
  def store_entry(entry, content_type)
    Tempfile.create([ "zip_entry", File.extname(entry.name) ], binmode: true) do |file|
      digest = ActiveStorage.checksum_implementation.new
      entry.get_input_stream do |input|
        while (chunk = input.read(CHUNK_SIZE))
          digest << chunk
          file.write(chunk)
        end
      end
      file.rewind

      blob = ActiveStorage::Blob.new(
        filename: File.basename(entry.name),
        content_type:,
        byte_size: file.size,
        checksum: digest.base64digest
      )
      # Сначала файл, потом запись: при сбое загрузки не остаётся blob без файла
      blob.upload_without_unfurling(file)
      blob.save!
      blob
    end
  end
end
