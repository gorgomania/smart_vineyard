class CleanupDemoUserJob < ApplicationJob
  queue_as :low_priority

  def perform(user_id)
    user = User.find_by(id: user_id, demo_temp: true)
    user&.destroy
  end
end
