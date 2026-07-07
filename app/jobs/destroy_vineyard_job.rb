class DestroyVineyardJob < ApplicationJob
  queue_as :default

  def perform(vineyard_id)
    vineyard = Vineyard.find(vineyard_id)

    vineyard.destroy
  end
end
