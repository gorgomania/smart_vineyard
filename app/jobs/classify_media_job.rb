class ClassifyMediaJob < ApplicationJob
  queue_as :default

  def perform(media_item_id)
    media_item = MediaItem.find_by(id: media_item_id)
    return unless media_item&.media&.attached?

    # Модель понимает только картинки; для видео не падаем, а просто перерисуем панель, чтобы снять «В обработке»
    media_item.classify! if media_item.media.image?

    Turbo::StreamsChannel.broadcast_replace_to(
      "media_item_#{media_item_id}",
      target: "analysis-panel-#{media_item_id}",
      partial: "media_items/analysis_panel",
      locals: { media_item: media_item, class_names: GrapeClassifier.class_names }
    )
  end
end
