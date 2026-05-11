class DestroyVineyardJob < ApplicationJob
  queue_as :default

  def perform(vineyard_id)
    # Удаляем сам виноградник (обходим default_scope)
    vineyard = Vineyard.unscoped.find(vineyard_id)

    # Удаляем зависимости вручную
    vineyard.rows.destroy_all

    # Удаляем сам виноградник (БЕЗ вызова destroy)
    vineyard.class.unscoped.where(id: vineyard.id).delete_all
  end
end
