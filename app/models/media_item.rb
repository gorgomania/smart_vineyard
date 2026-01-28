class MediaItem < ApplicationRecord
  belongs_to :folder
  has_one_attached :media
  validate :validate_media_filename
  def validate_media_filename(proposed_filename = nil)
    filename = proposed_filename || media.filename.to_s
    if filename.length == 0
      errors.add(:media, "Имя не может быть пустым.")
    end
    files_in_same_folder = MediaItem.where(folder_id: folder_id).where.not(id: id).joins(media_attachment: :blob).where(active_storage_blobs: { filename: filename }).where(active_storage_attachments: { name: "media" })
    errors.add(:media, "Имя #{filename} уже используется.") if files_in_same_folder.present?
  end
end
