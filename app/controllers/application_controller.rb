class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  include Pundit::Authorization
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  before_action :authenticate_user!
  allow_browser versions: :modern
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  # Та же страница, что Rails отдаёт сам при 404 вне контроллеров
  def not_found
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false, content_type: "text/html"
  end

  # JSON-запросам (выбор ряда и куста, bush_select_controller) — 403 с JSON: редирект на HTML-страницу
  # fetch прошёл бы насквозь, и response.json() упал бы на разметке
  def user_not_authorized
    respond_to do |format|
      format.json { render json: { error: "В доступе отказано" }, status: :forbidden }
      format.any do
        flash[:alert] = "В доступе отказано"
        redirect_to folders_path
      end
    end
  end

  private

  # После выхода и удаления аккаунта — сразу на вход. По умолчанию Devise ведёт на главную,
  # та без входа перенаправляет ещё раз, и сообщение «Выход выполнен» / «Учётная запись удалена»
  # подменяется на «Необходимо войти»
  def after_sign_out_path_for(_scope)
    new_user_session_path
  end
end
