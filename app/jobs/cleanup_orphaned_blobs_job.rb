class CleanupOrphanedBlobsJob < ApplicationJob
  queue_as :low_priority

  # Удаляем ВСЕХ сироток (blob'ы без привязки к MediaItem)
  def perform
    # Находим все blob без привязки к MediaItem
    orphaned_blobs = ActiveStorage::Blob
      .left_joins(:attachments)
      .where(active_storage_attachments: { id: nil })

    count = orphaned_blobs.count

    orphaned_blobs.find_each do |blob|
      blob.purge
      Rails.logger.info "Deleted orphaned blob: #{blob.id} (#{blob.filename})"
    end

    Rails.logger.info "🧹 Cleaned up #{count} orphaned blobs"
  end
end
