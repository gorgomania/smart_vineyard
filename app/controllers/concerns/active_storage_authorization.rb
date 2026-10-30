# Контроллеры ActiveStorage наследуются от ActionController::Base, а не от ApplicationController:
# без этого файл отдавался любому, у кого есть ссылка (signed id бессрочный), даже без входа.
# Подключается в config/initializers/active_storage_authorization.rb
module ActiveStorageAuthorization
  extend ActiveSupport::Concern

  # В начало цепочки: у представлений set_representation сразу генерирует превью, а чужому
  # пользователю это делать незачем. Повторный prepend set_blob переносит его, а не дублирует
  included do
    prepend_before_action :authorize_blob_owner!
    prepend_before_action :set_blob
    prepend_before_action :authenticate_user!
  end

  private

  # Блоб может быть общим с демо-копиями: достаточно, чтобы хоть одно его вложение было у файла пользователя
  def authorize_blob_owner!
    owned = MediaItem.joins(:folder)
                     .where(folders: { user_id: current_user.id })
                     .where(id: @blob.attachments.where(record_type: "MediaItem").select(:record_id))
                     .exists?

    head :not_found unless owned
  end
end
