# SMTP-настройки из окружения, общие для development и production: Яндекс по
# умолчанию, другой сервер задаётся переменными SMTP_*. Загружается из файлов
# окружений, то есть до автозагрузки, поэтому лежит в config/, а не в app/.
module SmtpSettings
  def self.from_env
    {
      address: ENV.fetch("SMTP_ADDRESS", "smtp.yandex.ru"),
      port: ENV.fetch("SMTP_PORT", "465").to_i,
      domain: ENV.fetch("SMTP_DOMAIN", "yandex.ru"),
      user_name: ENV["SMTP_USER_NAME"],
      password: ENV["SMTP_PASSWORD"],
      authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain"),
      ssl: boolean("SMTP_SSL", "true"),
      tls: boolean("SMTP_TLS", "false"),
      enable_starttls_auto: boolean("SMTP_ENABLE_STARTTLS_AUTO", "false"),
      open_timeout: ENV.fetch("SMTP_OPEN_TIMEOUT", "10").to_i,
      read_timeout: ENV.fetch("SMTP_READ_TIMEOUT", "10").to_i
    }
  end

  def self.boolean(name, default)
    ActiveModel::Type::Boolean.new.cast(ENV.fetch(name, default))
  end
  private_class_method :boolean
end
