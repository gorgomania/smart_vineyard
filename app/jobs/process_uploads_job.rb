class ProcessUploadsJob < ApplicationJob
  queue_as :default
  discard_on_deleted_arguments # папку удалили раньше, чем задача началась

  # Большая пачка обрабатывается не мгновенно: показываем файлы по мере появления, но не чаще этого.
  # Интервал меряем монотонными часами: системные могут прыгнуть (синхронизация времени, WSL2),
  # и тогда обновления сыпались бы подряд или замирали до тех пор, пока часы не догонят
  REFRESH_INTERVAL = 2.seconds

  def perform(folder, signed_blob_ids)
    last_refresh_at = monotonic_now
    media_item_ids = []
    # Имена папки — один раз на пачку, а не на каждый файл
    taken_names = MediaItem.filenames_in_folder(folder.id)

    signed_blob_ids.each do |signed_id|
      blob = ActiveStorage::Blob.find_signed(signed_id)
      # Уже прикреплён: форму отправили повторно (двойной клик, «Назад»). Второй файл с тем же блобом
      # переименовывал бы первый вместе с собой
      next if blob.nil? || blob.attachments.exists?

      media_item = MediaItem.new(folder_id: folder.id)
      media_item.media.attach(blob)
      media_item.normalize_filename!(taken_names)
      next unless media_item.save

      media_item_ids << media_item.id
      ClassifyMediaJob.perform_later(media_item.id) if blob.content_type.start_with?("image/")

      if monotonic_now - last_refresh_at >= REFRESH_INTERVAL
        folder.broadcast_refresh
        last_refresh_at = monotonic_now
      end
    end

    # На кусты по имени «Ряд N Куст M» — общей задачей, как и файлы из архива: одна логика привязки,
    # и кусты читаются в момент привязки, а не в начале длинной пачки (их могли пересоздать)
    DistributeMediaToBushesJob.perform_later(folder.id, media_item_ids) if folder.vineyard_id && media_item_ids.any?
    folder.broadcast_new_files
  end

  private

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
