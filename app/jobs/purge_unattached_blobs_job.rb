class PurgeUnattachedBlobsJob < ApplicationJob
  queue_as :low_priority

  BATCH_SIZE = 500

  # Удаляет блобы, на которые больше никто не ссылается, вместе с их миниатюрами. Блобы, всё ещё
  # прикреплённые к другим записям (общие с демо-копиями), не трогает.
  # Пачкой в несколько SQL-запросов: штатный blob.purge делал ~17 запросов на файл и ставил отдельную
  # задачу на удаление миниатюры — папка на 1500 файлов чистилась минуты
  def perform(blob_ids)
    files = ActiveStorage::Blob.transaction do
      # FOR UPDATE: если блоб прямо сейчас прикрепляют, вставка вложения дождётся нас и упадёт на внешнем ключе,
      # а не оставит вложение без файла
      blobs = ActiveStorage::Blob.where(id: blob_ids).where.missing(:attachments)
                                 .lock("FOR UPDATE OF active_storage_blobs")
                                 .pluck(:id, :key, :service_name, :content_type)
      next [] if blobs.empty?

      ids = blobs.map(&:first)
      variant_ids = ActiveStorage::VariantRecord.where(blob_id: ids).pluck(:id)
      # Файлы миниатюр (вложения VariantRecord) и превью ActiveStorage (preview_image самого блоба)
      dependents = ActiveStorage::Attachment.where(record_type: "ActiveStorage::VariantRecord", record_id: variant_ids)
                                            .or(ActiveStorage::Attachment.where(record_type: "ActiveStorage::Blob", record_id: ids))
      dependent_blobs = ActiveStorage::Blob.where(id: dependents.select(:blob_id))
                                           .pluck(:id, :key, :service_name, :content_type)

      dependents.delete_all
      ActiveStorage::VariantRecord.where(id: variant_ids).delete_all
      ActiveStorage::Blob.where(id: ids + dependent_blobs.map(&:first)).delete_all

      blobs + dependent_blobs
    end

    # Файлы — после коммита: если транзакция откатится, они ещё нужны
    files.each do |_id, key, service_name, content_type|
      service = ActiveStorage::Blob.services.fetch(service_name)
      service.delete(key)
      service.delete_prefixed("variants/#{key}/") if content_type&.start_with?("image") # как Blob#delete
    end
  end

  def self.enqueue_in_batches(blob_ids)
    ActiveJob.perform_all_later(blob_ids.each_slice(BATCH_SIZE).map { |batch| new(batch) })
  end
end
