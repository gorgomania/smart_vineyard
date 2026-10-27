class DemoSessionsController < ApplicationController
  skip_before_action :authenticate_user!

  def create
    user = DemoCloneService.call
    CleanupDemoUserJob.set(wait: 24.hours).perform_later(user.id)
    sign_in user
    redirect_to root_path
  rescue ActiveRecord::RecordNotFound
    redirect_to new_user_session_path, alert: "Демо недоступно"
  end
end
