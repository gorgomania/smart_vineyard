class NormalizeMediaFilenamesJob < ApplicationJob
  queue_as :default
  queue_with_priority PREVIEW_PRIORITY

  # Файлы одной пачки (обычно из одного архива): имена папки загружаем один раз, дальше занятые отмечает
  # normalize_filename!. Порядок — по id: из двух одинаковых имён своё сохраняет первый файл
  def perform(media_item_ids)
    MediaItem.where(id: media_item_ids).includes(media_attachment: :blob).order(:id).group_by(&:folder_id)
             .each do |folder_id, media_items|
      taken = MediaItem.filenames_in_folder(folder_id, except_ids: media_items.map(&:id))
      media_items.each { |media_item| media_item.media.blob.save if media_item.normalize_filename!(taken) }
    end
  end
end
