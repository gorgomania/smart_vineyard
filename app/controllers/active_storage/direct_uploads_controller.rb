class ActiveStorage::DirectUploadsController < ApplicationController
  # Как в штатном ActiveStorage::BaseController: хост для URL загрузки (сервис :local) берётся из запроса.
  # Без этого в production — "Missing host to link to!" (в development спасал routes.default_url_options)
  include ActiveStorage::SetCurrent

  # Сервис :local проверяет срок токена, когда Puma уже приняла всё тело запроса. Со штатными 5 минутами
  # файл до 1 ГБ, который грузится дольше, дошёл бы до конца и получил отказ. Больше таймаута загрузки
  # (uploadTimeoutSeconds в чарте, 1 час) с запасом на подсчёт checksum в браузере
  UPLOAD_URL_EXPIRES_IN = 2.hours

  # Те же ограничения, что в upload_controller.js, но на сервере: скрипт в обход формы иначе залил бы что угодно.
  # Обойти заявленный размер нельзя — сервис :local при загрузке сверяет Content-Length с byte_size
  MAX_BYTE_SIZE = 1.gigabyte
  ALLOWED_CONTENT_TYPES = %r{\A(image|video)/}

  def create
    unless allowed_upload?
      return render json: { error: "Можно загружать картинки, видео и ZIP-архивы до 1 ГБ" }, status: :unprocessable_content
    end

    blob = ActiveStorage::Blob.create_before_direct_upload!(**blob_args)
    render json: blob.as_json(root: false, methods: :signed_id).merge(
      "direct_upload" => {
        "url" => blob.service_url_for_direct_upload(expires_in: UPLOAD_URL_EXPIRES_IN),
        "headers" => blob.service_headers_for_direct_upload
      }
    )
  end

  private

  def allowed_upload?
    size = Integer(blob_args[:byte_size], exception: false)
    return false unless size&.between?(1, MAX_BYTE_SIZE)

    # ZIP узнаём по расширению, как и форма: тип у архивов разный (application/zip, application/x-zip-compressed, пустой)
    blob_args[:content_type].to_s.match?(ALLOWED_CONTENT_TYPES) || blob_args[:filename].to_s.downcase.end_with?(".zip")
  end

  def blob_args
    params.require(:blob)
          .permit(:filename, :byte_size, :checksum, :content_type, :record_type, :record_id, metadata: {})
          .to_h
          .symbolize_keys
          .merge(metadata: { "user_id" => current_user.id })
  end
end
