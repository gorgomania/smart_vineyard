class MediaItem < ApplicationRecord
  belongs_to :folder
  has_one_attached :media
  has_one_attached :video_preview
  validate :validate_media_filename
  after_commit :generate_preview, on: [ :create ]

  def validate_media_filename(proposed_filename = nil)
    filename = proposed_filename || media.filename.to_s
    if filename.length == 0
      errors.add(:media, "Имя не может быть пустым.")
    end
    files_in_same_folder = MediaItem.where(folder_id: folder_id).where.not(id: id).joins(media_attachment: :blob).where(active_storage_blobs: { filename: filename }).where(active_storage_attachments: { name: "media" })
    errors.add(:media, "Имя #{filename} уже используется.") if files_in_same_folder.present?
  end

  private

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

      video_preview.attach(
        io: File.open(preview_path),
        filename: "preview_#{blob.filename.base}.jpg",
        content_type: "image/jpeg"
      )
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
