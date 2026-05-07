class MediaItem < ApplicationRecord
  belongs_to :folder
  belongs_to :bush, optional: true

  has_one_attached :media
  has_one_attached :video_preview, dependent: :purge_later
  after_commit :generate_preview, on: :create, dependent: :purge_later
  validates :bush_id, uniqueness: true, if: :bush_id_present?
  validate :validate_media_filename

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
      ai_classification: result[:top_class],
      ai_confidence: result[:confidence],
      ai_class_id: result[:class_id],
      ai_classified_at: Time.current,
      ai_full_results: result[:predictions]
    )
  end

private

  def bush_id_present?
    bush_id.present?  # проверяем только если не nil
  end

  def validate_media_filename
    filename = media.filename.to_s
    if filename.length == 0
      errors.add(:media, "Имя не может быть пустым.")
    else
      files_in_same_folder = MediaItem.where(folder_id: folder_id).where.not(id: id).joins(media_attachment: :blob).where(active_storage_attachments: { name: "media" })
      index = 0
      filename_is_not_valid = true
      while filename_is_not_valid
        filename_is_not_valid = false
        files_in_same_folder.each do |file|
          if index == 0
            if file.media.filename == filename
              index += 1
              filename_is_not_valid = true
              break
            end
          else
            if file.media.filename == filename + " (" + index.to_s() + ")"
              index += 1
              filename_is_not_valid = true
              break
            end
          end
        end
      end
      if index == 0
        media.blob.update!(filename: filename)
      else
        media.blob.update!(filename: filename + " (" + index.to_s() + ")")
      end
    end
  end

  def generate_preview
    return unless media.attached? && media.video?
    return if video_preview.attached?
    # Получаем blob
    blob = media.blob
    # Получаем путь к файлу
    file_path = blob.service.send(:path_for, blob.key)
    duration = get_video_duration(file_path)
    # Вычисляем время для скриншота (10% от продолжительности, но не более 30 секунд)
    screenshot_time = duration * 0.1
    # Форматируем время для FFmpeg (HH:MM:SS.ss)
    time_formatted = format_time(screenshot_time)
    # Используем FFmpeg для создания превью
    preview_path = Rails.root.join("tmp", "preview_#{id}.jpg")

    # Берем кадр на 1-й секунде
    system(
      "ffmpeg", "-i", file_path,
      "-ss", time_formatted,
      "-vframes", "1",
      "-q:v", "2",
      preview_path.to_s
    )
    file = File.open(preview_path)
    video_preview.attach(
      io: file,
      filename: "preview_#{blob.filename.base}.jpg",
      content_type: "image/jpeg"
    )
    file.close
  ensure
    # Удаляем временный файл в любом случае
    File.delete(preview_path) if preview_path && File.exist?(preview_path)
  end

  def get_video_duration(file_path)
    # Используем FFprobe для получения информации о видео
    cmd = "ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 #{Shellwords.escape(file_path.to_s)}"
    result = `#{cmd}`
    duration = result.to_f
    duration
  end

  def format_time(seconds)
    # Конвертируем секунды в формат HH:MM:SS.ss
    hours = seconds.to_i / 3600
    minutes = (seconds.to_i % 3600) / 60
    secs = seconds % 60
    sprintf("%02d:%02d:%05.2f", hours, minutes, secs)
  end
end
