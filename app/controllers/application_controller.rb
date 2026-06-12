class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  include Pundit::Authorization
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  before_action :authenticate_user!
  allow_browser versions: :modern
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def not_found
    render "/errors/404", status: :not_found, formats: [ :html ]
  end

  def user_not_authorized
    flash[:alert] = "В доступе отказано"
    redirect_to folders_path
  end
end
