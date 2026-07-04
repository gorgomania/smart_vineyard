class DestroyVineyardJob < ApplicationJob
  queue_as :default

  def perform(vineyard_id)
    vineyard = Vineyard.find(vineyard_id)

    # Удаляем зависимости вручную
    vineyard.rows.destroy_all

    # Удаляем сам виноградник (БЕЗ вызова destroy)
    vineyard.delete
  end
end
