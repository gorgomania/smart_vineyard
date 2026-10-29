class DemoSessionsController < ApplicationController
  # Свой store: Rails.cache в production не настроен, а в test это null_store.
  # Web — один под с одним процессом Puma, поэтому счётчики в памяти общие для всех запросов
  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

  skip_before_action :authenticate_user!

  # Каждый запрос создаёт пользователя и копию данных мастера — ограничиваем и по IP, и в целом
  rate_limit to: 10, within: 1.hour, store: RATE_LIMIT_STORE, name: "per_ip",
             with: -> { redirect_to new_user_session_path, alert: "Слишком много демо-входов. Попробуйте позже" }
  rate_limit to: 100, within: 1.hour, store: RATE_LIMIT_STORE, name: "global", by: -> { "all" },
             with: -> { redirect_to new_user_session_path, alert: "Демо временно недоступно. Попробуйте позже" }

  def create
    user = DemoCloneService.call
    CleanupDemoUserJob.set(wait: 24.hours).perform_later(user.id)
    sign_in user
    redirect_to root_path
  rescue ActiveRecord::RecordNotFound
    redirect_to new_user_session_path, alert: "Демо недоступно"
  end
end
