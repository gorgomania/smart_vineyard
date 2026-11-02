require "capybara/cuprite"

# System-тесты гоняют настоящий headless Chrome через протокол DevTools (Cuprite/Ferrum), без chromedriver.
# Видимое окно для отладки: HEADLESS=false bundle exec rspec spec/system
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1280, 900 ],
    headless: ENV["HEADLESS"] != "false",
    # Ошибка в JS-консоли страницы роняет тест: иначе сломанный Stimulus-контроллер проявился бы
    # только как «не нашёл элемент» через default_max_wait_time
    js_errors: true,
    process_timeout: 30, # первый запуск Chrome в WSL и на раннере CI бывает небыстрым
    timeout: 15,
    # В контейнере CI песочница Chrome недоступна
    browser_options: ENV["CI"] ? { "no-sandbox" => nil } : {}
  )
end

Capybara.server = :puma, { Silent: true }
Capybara.default_max_wait_time = 5

RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :cuprite }

  # sign_in через Warden: сервер Capybara работает в том же процессе
  config.include Devise::Test::IntegrationHelpers, type: :system
end
