require "zip"

class ProcessZipJob < ApplicationJob
  queue_as :default

  def perform(folder, zip_path)
    # Создаём уникальную папку для этого ZIP
    zip_basename = File.basename(zip_path, ".*")
    temp_extract_dir = Rails.root.join("tmp", "zip_extract", zip_basename)
    FileUtils.mkdir_p(temp_extract_dir)
    # MIME типы
    mime_types = {
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".png" => "image/png",
      ".webp" => "image/webp",
      ".mp4" => "video/mp4"
    }

    # Сбор данных
    media_items_data = []
    blobs_data = []
    attachments_data = []

    Zip::File.open(zip_path) do |zip_file|
      entries = zip_file.select { |e| e.file? && [ ".jpg", ".jpeg", ".png", ".webp", ".mp4" ].include?(File.extname(e.name).downcase) }

      entries.each_with_index do |entry, index|
        ext = File.extname(entry.name).downcase
        content = entry.get_input_stream.read
        filename = File.basename(entry.name)

        # Подготавливаем MediaItem
        media_items_data << {
          folder_id: folder.id,
          created_at: Time.current,
          updated_at: Time.current
        }

        # Пока что сохраняем файл во временное место для batch upload
        temp_path = File.join(temp_extract_dir.to_s, filename.force_encoding("UTF-8"))
        FileUtils.mkdir_p(File.dirname(temp_path))
        File.binwrite(temp_path, content)

        blobs_data << {
          temp_path: temp_path,
          filename: filename,
          content_type: mime_types[ext],
          index: index
        }
      end
    end

    # Массовое создание MediaItem
    media_items_result = MediaItem.insert_all!(media_items_data, returning: [ :id ])
    media_item_ids = media_items_result.map { |r| r["id"] }

    # Массовое создание Blob и Attachment
    blob_results = []
    blobs_data.each_with_index do |blob_data, i|
      blob = ActiveStorage::Blob.create_and_upload!(
        io: File.open(blob_data[:temp_path]),
        filename: blob_data[:filename],
        content_type: blob_data[:content_type]
      )
      blob_results << blob

      # Удаляем временный файл
      File.delete(blob_data[:temp_path]) if File.exist?(blob_data[:temp_path])
    end

    # Массовое создание Attachment
    attachments_data = blob_results.each_with_index.map do |blob, i|
      {
        name: "media",
        record_type: "MediaItem",
        record_id: media_item_ids[i],
        blob_id: blob.id,
        created_at: Time.current
      }
    end

    ActiveStorage::Attachment.insert_all!(attachments_data)

    # Очистка временной папки
    FileUtils.rm_rf(temp_extract_dir)

    # Запускаем распределение медиафайлов по кустам
    DistributeMediaToBushesJob.perform_later(media_item_ids)

    # Запуск классификации для всех
    media_item_ids.each_with_index do |media_id, index|
      if blob_results[index].content_type.start_with?("image/")
        ClassifyMediaJob.perform_later(media_id)
        GenerateImagePreviewJob.perform_later(media_id)
      elsif blob_results[index].content_type.start_with?("video/")
        GenerateVideoPreviewJob.perform_later(media_id)
      end
    end

    NormalizeMediaFilenamesJob.perform_later(media_item_ids)

  rescue => e
    puts "Ошибка обработки ZIP: #{e.message}"
    puts e.backtrace.first(5)
    raise e
  end
end
