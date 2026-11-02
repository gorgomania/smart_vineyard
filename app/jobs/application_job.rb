class ApplicationJob < ActiveJob::Base
  # Порядок внутри очереди (solid_queue: меньше — раньше; между очередями приоритеты не сравниваются).
  # Без приоритета задача идёт с 0. В heavy: распаковка ZIP → классификация → превью;
  # в default: прикрепление файлов и привязка к кустам → нормализация имён
  CLASSIFICATION_PRIORITY = 10
  PREVIEW_PRIORITY = 20 # превью картинок и видео, нормализация имён: в проводнике превью при нужде сделает web

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Записи в аргументах передаются GlobalID: если запись удалили до начала задачи, ActiveJob падает
  # с DeserializationError ещё до perform, и discard_on ActiveRecord::RecordNotFound его не ловит.
  # Отбрасываем только этот случай — другие причины (нет связи с БД) пусть падают как обычно
  def self.discard_on_deleted_arguments
    rescue_from ActiveJob::DeserializationError do |error|
      raise error unless error.cause.is_a?(ActiveRecord::RecordNotFound)

      Rails.logger.info "#{self.class.name}: запись из аргументов уже удалена, задача отброшена"
    end
  end
end
