class DestroyVineyardJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(vineyard_id)
    Vineyard.find(vineyard_id).destroy!
  end
end
