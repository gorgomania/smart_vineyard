require "zip"

class ProcessZipJob < ApplicationJob
  queue_as :default

  def perform(folder_id, zip_path)
    start_time = Time.current
    puts "Время запуска: #{start_time.strftime('%Y-%m-%d %H:%M:%S')}"
    folder = Folder.find(folder_id)
    vineyard = folder.vineyard

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

    # Кэш кустов
    bush_cache = {}

    if vineyard.present?
      vineyard.bushes.joins(:row).select("rows.row_number, bushes.bush_number, bushes.id").each do |bush|
        bush_cache["#{bush.row_number}_#{bush.bush_number}"] = bush.id
      end
    end

    # 🟢 Заранее узнаём, какие кусты уже имеют медиа
    existing_bush_ids = MediaItem.where.not(bush_id: nil).pluck(:bush_id).to_set

    # Сбор данных
    media_items_data = []
    blobs_data = []
    attachments_data = []

    Zip::File.open(zip_path) do |zip_file|
      entries = zip_file.select { |e| e.file? && [ ".jpg", ".jpeg", ".png", ".webp", ".mp4" ].include?(File.extname(e.name).downcase) }
      total_files = entries.count
      puts "Всего файлов для обработки: #{total_files}"

      entries.each_with_index do |entry, index|
        ext = File.extname(entry.name).downcase
        content = entry.get_input_stream.read
        filename = File.basename(entry.name)

        # Определяем bush_id по имени файла
        bush_id = nil
        if vineyard.present?
          clean_filename = filename.force_encoding("UTF-8")
          match = clean_filename.match(/(?:Ряд|ряд)\s*(\d+)\s*(?:Куст|куст)\s*(\d+)/)
          if match
            row_num = match[1].to_i
            bush_num = match[2].to_i
            bush_id = bush_cache["#{row_num}_#{bush_num}"]
            # 🟢 ПРОВЕРКА НА ДУБЛИКАТ
            if existing_bush_ids.include?(bush_id)
              bush_id = nil
            else
              existing_bush_ids.add(bush_id)
            end
          end
        end

        # Подготавливаем MediaItem
        media_items_data << {
          folder_id: folder_id,
          bush_id: bush_id,
          ai_full_results: {},
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

        if (index + 1) % 100 == 0 || (index + 1) == total_files
          percent = ((index + 1).to_f / total_files * 100).round(1)
          elapsed = (Time.current - start_time).round(1)
          puts "Распаковка: #{index + 1}/#{total_files} (#{percent}%) | #{elapsed} сек"
        end
      end
    end

    # Массовое создание MediaItem
    puts "Создаём MediaItem..."
    media_items_result = MediaItem.insert_all!(media_items_data, returning: [ :id ])
    media_item_ids = media_items_result.map { |r| r["id"] }

    # Массовое создание Blob и Attachment
    puts "Создаём Blob и Attachment..."

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

      if (i + 1) % 100 == 0 || (i + 1) == blobs_data.length
        percent = ((i + 1).to_f / blobs_data.length * 100).round(1)
        puts "Blob: #{i + 1}/#{blobs_data.length} (#{percent}%)"
      end
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

    NormalizeMediaFilenamesJob.perform_later(media_item_ids)

    total_time = (Time.current - start_time).round(1)
    puts "ZIP архив обработан: папка #{folder_id}, файлов: #{media_items_data.size}"
    puts "Общее время: #{total_time} секунд (около #{(total_time / 60).round(1)} минут)"

    # Очистка временной папки
    FileUtils.rm_rf(temp_extract_dir)

    # Запуск классификации для всех (асинхронно)
    media_item_ids.each do |media_id|
      ClassifyMediaJob.perform_later(media_id)
    end

  rescue => e
    puts "Ошибка обработки ZIP: #{e.message}"
    puts e.backtrace.first(5)
    raise e
  end
end
