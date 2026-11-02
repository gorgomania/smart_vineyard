# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/utils", under: "utils"

pin "@rails/activestorage", to: "activestorage.esm.js"
pin "chart.js", to: "chart.umd.js"
# MD5 на WebAssembly для проверки файлов перед загрузкой (utils/file_checksum). Без предзагрузки: 230 КБ (все
# алгоритмы библиотеки) нужны только странице загрузки, их подгружает import() при первой проверке
pin "hash-wasm", preload: false # @4.12.0
