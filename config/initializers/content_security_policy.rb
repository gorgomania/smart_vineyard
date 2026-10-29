# Be sure to restart your server when you modify this file.

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :https, :data, :blob
    policy.object_src  :none
    policy.media_src   :self, :blob
    policy.frame_src   :none

    # Яндекс Карты 2.1 динамически подгружает скрипты с нескольких доменов
    policy.script_src :self,
                      "https://api-maps.yandex.ru",
                      "https://yastatic.net",
                      "https://core.maps.yandex.ru",
                      "https://core-renderer-tiles.maps.yandex.net"

    # Яндекс Карты внедряет inline-стили — без unsafe-inline карта не отображается
    policy.style_src :self, :unsafe_inline, "https://yastatic.net"

    # ActionCable (Solid Cable) + ActiveStorage direct uploads + Яндекс API
    policy.connect_src :self, :https, :wss,
                       "https://*.maps.yandex.ru",
                       "https://*.maps.yandex.net"

    policy.worker_src :self, :blob
  end

  # Nonce для importmap и inline-скриптов Rails
  # Случайный на каждый запрос: session.id одинаков всю сессию, а утёкший nonce не должен работать дальше
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
