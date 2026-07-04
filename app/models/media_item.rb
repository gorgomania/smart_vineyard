class MediaItem < ApplicationRecord
  belongs_to :folder
  belongs_to :bush, optional: true

  has_one_attached :media, dependent: :purge_later
  has_one_attached :video_preview, dependent: :purge_later

  after_create_commit :generate_video_preview
  after_create_commit :generate_image_preview

  validates :bush_id, uniqueness: true, if: :bush_id_present?

public

  def row_number
    bush&.row&.row_number
  end

  def vineyard_name
    bush&.vineyard&.name
  end

  def classify!
    return false unless media.attached?

    result = GrapeClassifier.predict_from_media_item(self)

    update!(
      ai_class_id: result[:class_id],
      ai_confidence: result[:confidence],
      ai_full_results: result[:predictions],
      ai_classified_at: Time.current
    )
  end

  def normalize_filename!
    return unless media.attached?

    blob = media.blob
    current_filename = blob.filename.to_s
    base_name = current_filename.gsub(/\.[^.]+\z/, "").strip
    extension = blob.filename.extension_with_delimiter

    # 🚀 Загружаем все имена файлов в папке одним запросом
    existing_names = MediaItem
      .where(folder_id: folder_id)
      .where.not(id: id)
      .joins(media_attachment: :blob)
      .where(active_storage_attachments: { name: "media" })
      .pluck("active_storage_blobs.filename")  # ← pluck вместо загрузки объектов
      .map(&:to_s)

    final_name = "#{base_name}#{extension}"

    if existing_names.include?(final_name)
      index = 2
      loop do
        candidate = "#{base_name}(#{index})#{extension}"
        unless existing_names.include?(candidate)
          final_name = candidate
          break
        end
        index += 1
      end
    end

    if final_name != current_filename
      blob.filename = final_name
      true
    else
      false
    end
  end

private

  def bush_id_present?
    bush_id.present?  # проверяем только если не nil
  end

  def generate_image_preview
    return unless media.attached? && media.image?
    GenerateImagePreviewJob.perform_later(id)
  end

  def generate_video_preview
    return unless media.attached? && media.video?
    return if video_preview.attached?
    GenerateVideoPreviewJob.perform_later(id)
  end
end
