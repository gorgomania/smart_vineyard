namespace :folder do
  desc "Загрузить фиксированный ZIP архив"
  task upload_zip: :environment do
    # Фиксированный путь
    file_path = "/mnt/c/Users/GEORGE/Desktop/Нейронка/vineyard_dataset.zip"

    unless File.exist?(file_path)
      puts "Файл не найден: #{file_path}"
      exit
    end

    puts "Файл: #{file_path}"
    puts "Размер: #{File.size(file_path) / 1024 / 1024} МБ"
    puts "Введите ID папки (folder_id):"
    folder_id = STDIN.gets.to_i

    if folder_id <= 0
      puts "Некорректный ID папки"
      exit
    end

    unless Folder.exists?(id: folder_id)
      puts "Папка с ID #{folder_id} не найдена"
      exit
    end

    puts "Начинаю обработку..."
    ProcessZipJob.perform_now(folder_id, file_path)
    puts "Готово!"
  end
end
