class Folder < ApplicationRecord
  belongs_to :user
  belongs_to :parent, class_name: "Folder", optional: true
  belongs_to :vineyard, optional: true
  has_many :children, class_name: "Folder", foreign_key: :parent_id, dependent: :destroy
  has_many :media_items, dependent: :destroy

  validates :title, presence: { message: "Имя не может быть пустым" }
  validates :title, uniqueness: { scope: [ :parent_id, :user_id ], message: "Имя папки уже используется" }
  validates :title, length: { maximum: 15, message: "Длина не более 15 символов" }
  validates :vineyard_id, uniqueness: true, if: :vineyard_id_present?

  # Быстрое удаление папок со всем поддеревом за несколько SQL-запросов вместо destroy каждой записи.
  # Вложенные папки и файлы удаляет FK ON DELETE CASCADE (folders.parent_id, media_items.folder_id);
  # вложения полиморфные, без FK, поэтому их удаляем сами. Файлы с диска убирает PurgeUnattachedBlobsJob
  # после коммита. Колбэки MediaItem не вызываются: всё, что они делали, покрыто здесь
  def self.delete_trees!(root_ids)
    root_ids = Array(root_ids)
    return if root_ids.empty?

    transaction do
      subtree = where(id: root_ids).select(:id)
      subtree_sql = <<~SQL.squish
        WITH RECURSIVE tree AS (
          #{subtree.to_sql}
          UNION ALL
          SELECT f.id FROM #{quoted_table_name} f JOIN tree ON f.parent_id = tree.id
        )
        SELECT id FROM tree
      SQL

      media_items = MediaItem.where("folder_id IN (#{subtree_sql})")
      attachments = ActiveStorage::Attachment.where(record_type: "MediaItem", record_id: media_items.select(:id))
      blob_ids = attachments.distinct.pluck(:blob_id)
      # Кусты этих виноградников освобождаются: открытые тепловые карты и статистика должны обновиться
      vineyard_ids = Bush.where(id: media_items.where.not(bush_id: nil).select(:bush_id)).distinct.pluck(:vineyard_id)
      attachments.delete_all
      where(id: root_ids).delete_all

      # Задачи — в другой БД (queue): ставим после коммита, иначе задача увидит ещё прикреплённые блобы.
      # Рассылка тоже после коммита: карта перечитает диагнозы уже без удалённых файлов
      ActiveRecord.after_all_transactions_commit do
        PurgeUnattachedBlobsJob.enqueue_in_batches(blob_ids)
        Vineyard.broadcast_diagnoses_changed(vineyard_ids)
      end
    end
  end

  def delete_tree!
    self.class.delete_trees!(id)
  end

  # Открытая страница папки (turbo_stream_from в folders/show) перезапрашивает себя и подтягивает новые файлы.
  # Повтор через несколько секунд — для страницы, открытой редиректом после загрузки: небольшая пачка
  # успевает обработаться раньше, чем страница подпишется на канал, и первый сигнал до неё не доходит
  def broadcast_new_files
    broadcast_refresh
    RefreshFolderJob.set(wait: 3.seconds).perform_later(self)
  end

  # Два одновременных запроса проходят валидацию оба, и второй упирается в уникальный индекс.
  # Превращаем это в обычную ошибку валидации: update вернёт false, а не 500
  def save(...)
    super
  rescue ActiveRecord::RecordNotUnique => e
    raise unless e.message.include?("index_folders_on_vineyard_id")

    errors.add(:vineyard_id, :taken)
    false
  end

  def title_path
    return [ title ] if parent.nil?
    parent.title_path + [ title ]
  end

  def id_path
    return [ id ] if parent.nil?
    parent.id_path + [ id ]
  end

  private

  def vineyard_id_present?
      vineyard_id.present?  # проверяем только если не nil
  end
end
