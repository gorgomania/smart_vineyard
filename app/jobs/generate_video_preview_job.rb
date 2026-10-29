require "open3"

class GenerateVideoPreviewJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(id)
    media_item = MediaItem.find(id)
    blob = media_item.media.blob
    preview_path = Rails.root.join("tmp", "preview_#{id}.jpg")

    blob.open do |tempfile|
      duration = get_video_duration(tempfile.path)
      screenshot_time = duration * 0.1
      time_formatted = format_time(screenshot_time)

      success = system(
        "ffmpeg", "-i", tempfile.path,
        "-ss", time_formatted,
        "-vframes", "1",
        "-q:v", "2",
        "-update", "1",
        preview_path.to_s
      )
      return unless success
    end

    File.open(preview_path) do |file|
      media_item.video_preview.attach(
        io: file,
        filename: "preview_#{blob.filename.base}.jpg",
        content_type: "image/jpeg"
      )
    end

    Turbo::StreamsChannel.broadcast_replace_to(
      "media_item_#{id}",
      target: "video-preview-#{id}",
      partial: "folders/video_preview",
      locals: { file: media_item }
    )
  ensure
    File.delete(preview_path) if preview_path && File.exist?(preview_path)
  end

private

  def get_video_duration(file_path)
    result, = Open3.capture2(
      "ffprobe", "-v", "error",
      "-show_entries", "format=duration",
      "-of", "default=noprint_wrappers=1:nokey=1",
      file_path.to_s
    )
    result.to_f
  end

  def format_time(seconds)
    # Конвертируем секунды в формат HH:MM:SS.ss
    hours = seconds.to_i / 3600
    minutes = (seconds.to_i % 3600) / 60
    secs = seconds % 60
    sprintf("%02d:%02d:%05.2f", hours, minutes, secs)
  end
end
