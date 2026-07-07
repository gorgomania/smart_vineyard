class DestroyVineyardJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(vineyard_id)
    vineyard = Vineyard.find(vineyard_id)

    vineyard.folder&.update_column(:vineyard_id, nil)
    vineyard.rows.destroy_all
    vineyard.delete
  end
end
