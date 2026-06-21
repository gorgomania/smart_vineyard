class CleanupOrphanedActiveStorageRecordsJob < ApplicationJob
  queue_as :low_priority

  def perform
    cleanup_blobs_without_attachments
    cleanup_attachments_with_missing_record
  end

private

  # Удаляем ВСЕХ сироток (blob'ы без привязки к MediaItem)
  def cleanup_blobs_without_attachments
    # Находим все blob без привязки к MediaItem
    orphaned_blobs = ActiveStorage::Blob
      .left_joins(:attachments)
      .where(active_storage_attachments: { id: nil })

    count = orphaned_blobs.count

    orphaned_blobs.find_each do |blob|
      blob.purge
      Rails.logger.info "Deleted orphaned blob: #{blob.id} (#{blob.filename})"
    end

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
        Rails.logger.warn "Model #{record_type} not found, purging #{count} attachments"
        attachments.find_each do |attachment|
          attachment.purge
          total_deleted += 1
        end
        next
      end

      attachments = ActiveStorage::Attachment.where(record_type: record_type)
      existing_ids = klass.unscoped.where(id: attachments.select(:record_id)).pluck(:id).to_set

      orphaned = attachments.reject { |a| existing_ids.include?(a.record_id) }

      Rails.logger.info "#{record_type}: #{orphaned.size} attachments with missing record"

      orphaned.each do |attachment|
        Rails.logger.info "Deleted orphaned attachment: #{attachment.id} " \
                           "(record_type=#{record_type}, record_id=#{attachment.record_id}, " \
                           "blob=#{attachment.blob&.filename})"
        attachment.purge
        total_deleted += 1
      end
    end

    Rails.logger.info "Cleaned up #{total_deleted} attachments with missing records"
  end
end
