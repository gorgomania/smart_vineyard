require "zip"

class ProcessZipJob < ApplicationJob
  queue_as :default

  def perform(folder_id, zip_path)
    folder = Folder.find(folder_id)
    vineyard = folder.vineyard

    # Открываем ZIP архив
    Zip::File.open(zip_path) do |zip_file|
      zip_file.each do |entry|
        next unless entry.file?

        # Проверяем расширение файла
        ext = File.extname(entry.name).downcase
        next unless [ ".jpg", ".jpeg", ".png", ".webp", ".mp4" ].include?(ext)

        # Создаем временный файл
        temp_file = Tempfile.new([ "upload", ext ])
        temp_file.binmode
        temp_file.write(entry.get_input_stream.read)
        temp_file.rewind

        # Создаем MediaItem
        media_item = MediaItem.new(folder_id: folder_id)
        media_item.media.attach(
          io: temp_file,
          filename: File.basename(entry.name),
          content_type: Rack::Mime.mime_type(ext)
        )

        if media_item.save && vineyard.present?
          # Очищаем от нежелательных символов
          filename = File.basename(entry.name).force_encoding("UTF-8")
          # Парсим имя файла для привязки к кусту
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

          # Запускаем классификацию для изображений
          if entry.name.match?(/\.(jpg|jpeg|png|webp)$/i)
            ClassifyMediaJob.perform_later(media_item.id)
          end
        end

        temp_file.close
        temp_file.unlink
      end
    end

    puts "ZIP архив обработан: папка #{folder_id}"
  rescue => e
    puts "Ошибка обработки ZIP: #{e.message}"
    raise e
  end
end
