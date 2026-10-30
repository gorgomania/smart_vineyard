class ApplicationJob < ActiveJob::Base
  # Порядок внутри очереди default (solid_queue: меньше — раньше). Без приоритета задача идёт с 0:
  # так распаковка, прикрепление файлов и привязка к кустам обгоняют всё остальное
  CLASSIFICATION_PRIORITY = 10
  PREVIEW_PRIORITY = 20 # превью картинок и видео, нормализация имён: в проводнике превью при нужде сделает web

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
