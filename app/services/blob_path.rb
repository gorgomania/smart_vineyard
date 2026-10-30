# Путь к файлу blob'а для библиотек, которые читают с диска (rubyzip, vips, ffmpeg).
# Disk-сервис: файл уже лежит на PVC — отдаём его путь. blob.open скопировал бы его во временный файл
# (на диск ноды) и перечитал целиком ради MD5, а checksum и так сверен при загрузке.
# У остальных сервисов (S3 и т. п.) path_for нет — штатная выгрузка во временный файл
module BlobPath
  def self.open(blob, **options)
    if blob.service.respond_to?(:path_for)
      yield blob.service.path_for(blob.key)
    else
      blob.open(**options) { |file| yield file.path }
    end
  end
end
