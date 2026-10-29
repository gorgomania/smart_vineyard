class PurgeUnattachedBlobsJob < ApplicationJob
  queue_as :low_priority

  BATCH_SIZE = 500

  # Удаляет файлы блобов, на которые больше никто не ссылается. Блобы, всё ещё прикреплённые
  # к другим записям (общие с демо-копиями), не трогает
  def perform(blob_ids)
    ActiveStorage::Blob.where(id: blob_ids).where.missing(:attachments).find_each(&:purge)
  end

  def self.enqueue_in_batches(blob_ids)
    ActiveJob.perform_all_later(blob_ids.each_slice(BATCH_SIZE).map { |batch| new(batch) })
  end
end
