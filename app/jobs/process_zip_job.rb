require "zip"

class ProcessZipJob < ApplicationJob
  queue_as :heavy
  discard_on_deleted_arguments # папку или архив удалили раньше, чем задача началась

  MIME_TYPES = {
    ".jpg"  => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".png"  => "image/png",
    ".webp" => "image/webp",
    ".mp4"  => "video/mp4"
  }.freeze
  CHUNK_SIZE = 1.megabyte

  # Распакованный архив не должен забить диск (ZIP-бомба: мегабайты, которые разворачиваются в сотни гигабайт).
  # Файл — как при прямой загрузке, архив целиком — с запасом на тысячи фото. Размеры в заголовке архива
  # можно подделать, поэтому считаем и то, что реально распаковали
  MAX_ENTRIES = 10_000
  MAX_ENTRY_SIZE = 1.gigabyte
  MAX_TOTAL_SIZE = 10.gigabytes
  UTF8_NAME_FLAG = 0x800 # бит 11 в флагах записи: имя в UTF-8

  class ArchiveTooLarge < StandardError; end

  def perform(folder, zip_blob)
    media_items_data = []
    blob_results = []

    BlobPath.open(zip_blob) do |path|
      Zip::File.open(path) do |zip_file|
        entries = zip_file.select { |e| e.file? && MIME_TYPES.key?(File.extname(e.name).downcase) }
        check_declared_size!(entries)
        @extracted_bytes = 0

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
  rescue ArchiveTooLarge => e
    # Повтор не поможет: распакованное и сам архив убираем сразу
    Rails.logger.warn "ZIP отклонён (папка #{folder.id}): #{e.message}"
    blob_results.each { |b| b.purge rescue nil }
    zip_blob.purge
  rescue => e
    Rails.logger.error "Ошибка обработки ZIP: #{e.message}"
    Rails.logger.error e.backtrace.first(5)
    # Пока записи не сохранены, распакованные файлы — сироты. Архив не трогаем: задачу можно повторить,
    # а иначе его уберёт CleanupOrphanedActiveStorageRecordsJob через сутки
    blob_results.each { |b| b.purge rescue nil } unless media_item_ids
    raise e
  end

  private

  def check_declared_size!(entries)
    raise ArchiveTooLarge, "#{entries.size} файлов, допустимо #{MAX_ENTRIES}" if entries.size > MAX_ENTRIES
    raise ArchiveTooLarge, "файл больше #{MAX_ENTRY_SIZE / 1.gigabyte} ГБ" if entries.any? { |e| e.size > MAX_ENTRY_SIZE }
    raise ArchiveTooLarge, "распакованный больше #{MAX_TOTAL_SIZE / 1.gigabyte} ГБ" if entries.sum(&:size) > MAX_TOTAL_SIZE
  end

  # Имя файла в архиве. С флагом UTF-8 — как есть. Без флага пишут и UTF-8 (macOS, 7-Zip), и кодовую страницу
  # DOS: «Сжатая ZIP-папка» Windows кладёт русские имена в CP866. Байты не похожи на UTF-8 — читаем как CP866,
  # иначе «Ряд 1 Куст 1.jpg» превратился бы в мусор (или вовсе не записался в базу) и не попал на свой куст
  def entry_filename(entry)
    name = File.basename(entry.name).dup.force_encoding(Encoding::UTF_8)
    return name.scrub if name.valid_encoding? || (entry.gp_flags & UTF8_NAME_FLAG).nonzero?

    name.force_encoding(Encoding::CP866).encode(Encoding::UTF_8)
  end

  # Распаковываем запись один раз, считая checksum на лету. create_and_upload! с потоком из архива
  # распаковывал бы её дважды: для checksum и для записи
  def store_entry(entry, content_type)
    Tempfile.create([ "zip_entry", File.extname(entry.name) ], binmode: true) do |file|
      digest = ActiveStorage.checksum_implementation.new
      entry_bytes = 0
      entry.get_input_stream do |input|
        while (chunk = input.read(CHUNK_SIZE))
          entry_bytes += chunk.bytesize
          @extracted_bytes += chunk.bytesize
          raise ArchiveTooLarge, "файл больше #{MAX_ENTRY_SIZE / 1.gigabyte} ГБ" if entry_bytes > MAX_ENTRY_SIZE
          raise ArchiveTooLarge, "распаковано больше #{MAX_TOTAL_SIZE / 1.gigabyte} ГБ" if @extracted_bytes > MAX_TOTAL_SIZE

          digest << chunk
          file.write(chunk)
        end
      end
      file.rewind

      blob = ActiveStorage::Blob.new(
        filename: entry_filename(entry),
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
