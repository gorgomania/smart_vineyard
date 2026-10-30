class ApplicationJob < ActiveJob::Base
  # Порядок внутри очереди (solid_queue: меньше — раньше; между очередями приоритеты не сравниваются).
  # Без приоритета задача идёт с 0. В heavy: распаковка ZIP → классификация → превью;
  # в default: прикрепление файлов и привязка к кустам → нормализация имён
  CLASSIFICATION_PRIORITY = 10
  PREVIEW_PRIORITY = 20 # превью картинок и видео, нормализация имён: в проводнике превью при нужде сделает web

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
