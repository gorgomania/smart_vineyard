class DistributeMediaToBushesJob < ApplicationJob
  queue_as :default
  # Параллельная задача заняла куст между проверкой и UPDATE: при повторе он попадёт в occupied
  retry_on ActiveRecord::RecordNotUnique, wait: 1.second, attempts: 3

  FILENAME_PATTERN = /(?:Ряд|ряд)\s*(\d+)\s*(?:Куст|куст)\s*(\d+)/

  # Трогаем только файлы с именем «Ряд N Куст M»: такой файл оказывается на своём кусте или без куста.
  # Остальные файлы привязаны вручную — их не меняем, а их кусты считаем занятыми.
  #
  # media_item_ids: nil — вся папка (прикрепили/перекрепили/открепили виноградник, перегенерировали кусты),
  # массив — только эти файлы (новые из архива)
  def perform(folder_id, media_item_ids = nil)
    folder = Folder.find_by(id: folder_id)
    return unless folder

    scope = folder.media_items
    scope = scope.where(id: media_item_ids) if media_item_ids

    # [id, текущий bush_id, [ряд, куст]] — только файлы, подходящие под шаблон
    named = scope.joins(media_attachment: :blob)
      .order(:id)
      .pluck(:id, :bush_id, "active_storage_blobs.filename")
      .filter_map do |id, bush_id, filename|
        match = filename.match(FILENAME_PATTERN)
        [ id, bush_id, [ match[1].to_i, match[2].to_i ] ] if match
      end
    return if named.empty?

    bush_ids_by_coords = folder.vineyard&.bushes&.joins(:row)
      &.pluck("rows.row_number", "bushes.bush_number", "bushes.id")
      &.each_with_object({}) { |(row, bush, id), h| h[[ row, bush ]] = id } || {}

    named_ids = named.map(&:first)
    # Куст держит файл, который мы не трогаем (привязан вручную или из другой папки) — не отбираем
    occupied = MediaItem
      .where(bush_id: bush_ids_by_coords.values)
      .where.not(id: named_ids)
      .pluck(:bush_id)
      .to_set

    taken = Set.new
    changes = named.filter_map do |id, current_bush_id, coords|
      bush_id = bush_ids_by_coords[coords]
      # Один куст — один файл: "Ряд 1 Куст 1.jpg" и "Ряд 1 Куст 1(2).jpg" претендуют на один куст, берём первый
      bush_id = nil if bush_id.nil? || occupied.include?(bush_id) || !taken.add?(bush_id)
      [ id, bush_id ] if bush_id != current_bush_id
    end
    return if changes.empty?

    # Карты, где кусты освобождаются (откреплённый виноградник) и где занимаются
    changed_ids = changes.map(&:first)
    vineyard_ids = Bush.where(id: MediaItem.where(id: changed_ids).select(:bush_id)).distinct.pluck(:vineyard_id)
    vineyard_ids << folder.vineyard_id

    now = Time.current
    MediaItem.transaction do
      # Сначала освобождаем: иначе обмен кустами между двумя файлами упрётся в уникальный индекс
      MediaItem.where(id: changed_ids).update_all(bush_id: nil, updated_at: now)

      changes.reject { |_, bush_id| bush_id.nil? }.each_slice(1000) do |slice|
        placeholders = Array.new(slice.size, "WHEN ? THEN ?").join(" ")
        sql = MediaItem.sanitize_sql_array(
          [ "bush_id = CASE id #{placeholders} END, updated_at = ?", *slice.flatten, now ]
        )
        MediaItem.where(id: slice.map(&:first)).update_all(sql)
      end
    end

    # Классификация идёт параллельно и могла закончиться раньше, чем файл попал на куст, — тогда её сообщение
    # карте ушло без куста. Перечитывание подхватит и такие файлы
    Vineyard.broadcast_heatmap_refresh(vineyard_ids)
  end
end
