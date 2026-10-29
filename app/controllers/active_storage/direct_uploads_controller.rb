class ActiveStorage::DirectUploadsController < ApplicationController
  # Как в штатном ActiveStorage::BaseController: хост для URL загрузки (сервис :local) берётся из запроса.
  # Без этого в production — "Missing host to link to!" (в development спасал routes.default_url_options)
  include ActiveStorage::SetCurrent

  # Сервис :local проверяет срок токена, когда Puma уже приняла всё тело запроса. Со штатными 5 минутами
  # файл до 1 ГБ, который грузится дольше, дошёл бы до конца и получил отказ. Больше таймаута загрузки
  # (uploadTimeoutSeconds в чарте, 1 час) с запасом на подсчёт checksum в браузере
  UPLOAD_URL_EXPIRES_IN = 2.hours

  def create
    blob = ActiveStorage::Blob.create_before_direct_upload!(**blob_args)
    render json: blob.as_json(root: false, methods: :signed_id).merge(
      "direct_upload" => {
        "url" => blob.service_url_for_direct_upload(expires_in: UPLOAD_URL_EXPIRES_IN),
        "headers" => blob.service_headers_for_direct_upload
      }
    )
  end

  private

  def blob_args
    params.require(:blob)
          .permit(:filename, :byte_size, :checksum, :content_type, :record_type, :record_id, metadata: {})
          .to_h
          .symbolize_keys
          .merge(metadata: { "user_id" => current_user.id })
  end
end
