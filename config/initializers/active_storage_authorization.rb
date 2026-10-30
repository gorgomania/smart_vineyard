# Файлы отдаются только владельцу (app/controllers/concerns/active_storage_authorization.rb).
# DiskController не трогаем: его ссылки выдают только эти контроллеры, и живут они 5 минут
Rails.application.config.to_prepare do
  [
    ActiveStorage::Blobs::RedirectController,
    ActiveStorage::Blobs::ProxyController,
    ActiveStorage::Representations::RedirectController,
    ActiveStorage::Representations::ProxyController
  ].each { |controller| controller.include(ActiveStorageAuthorization) }
end
