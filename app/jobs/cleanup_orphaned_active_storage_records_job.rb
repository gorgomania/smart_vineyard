class CleanupOrphanedActiveStorageRecordsJob < ApplicationJob
  queue_as :low_priority

  # ZIP-архив живёт блобом без привязки, пока его не обработает ProcessZipJob
  ZIP_GRACE_PERIOD = 1.day

  # Сначала удаляем осиротевшие attachments, тогда их blob'ы уйдут в этом же прогоне
  def perform
    cleanup_attachments_with_missing_record
    cleanup_blobs_without_attachments
  end

private

  # Удаляем ВСЕХ сироток (blob'ы без единого attachment) — пачками, вместе с миниатюрами
  def cleanup_blobs_without_attachments
    orphaned_ids = ActiveStorage::Blob
      .left_joins(:attachments)
      .where(active_storage_attachments: { id: nil })
      .where("active_storage_blobs.created_at < ?", 1.hour.ago)
      # По расширению, а не content_type: его задаёт браузер (application/x-zip-compressed в Windows, иногда пусто)
      .where.not(
        "active_storage_blobs.filename ILIKE ? AND active_storage_blobs.created_at >= ?",
        "%.zip", ZIP_GRACE_PERIOD.ago
      )
      .pluck(:id)

    count = orphaned_ids.each_slice(PurgeUnattachedBlobsJob::BATCH_SIZE).sum { |ids| PurgeUnattachedBlobsJob.purge(ids) }

    Rails.logger.info "Cleaned up #{count} orphaned blobs"
  end

  # Случай 2: attachment ссылается на запись, которой больше нет
  def cleanup_attachments_with_missing_record
    total_deleted = 0

    ActiveStorage::Attachment.distinct.pluck(:record_type).each do |record_type|
      klass = record_type.safe_constantize

      # Если модель вообще не резолвится (была удалена из кода и т.п.) —
      # считаем все attachments этого типа orphaned.
      if klass.nil?
        attachments = ActiveStorage::Attachment.where(record_type: record_type)
        count = attachments.count
        Rails.logger.warn "Model #{record_type} not found, deleting #{count} attachments"
        total_deleted += attachments.delete_all
        next
      end

      # Одним DELETE с подзапросом, без выгрузки id в Ruby. Только delete: blob может быть общим (демо-копии),
      # его удалит cleanup_blobs_without_attachments
      deleted = ActiveStorage::Attachment.where(record_type: record_type)
                                         .where.not(record_id: klass.unscoped.select(:id))
                                         .delete_all

      Rails.logger.info "#{record_type}: deleted #{deleted} attachments with missing record" if deleted.positive?
      total_deleted += deleted
    end

    Rails.logger.info "Cleaned up #{total_deleted} attachments with missing records"
  end
end
