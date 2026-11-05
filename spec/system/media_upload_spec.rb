require "rails_helper"

# Полный путь загрузки в браузере: Stimulus-контроллер upload грузит файл через DirectUpload, форма уходит
# с signed id, ProcessUploadsJob создаёт файл, а открытая страница папки сама перерисовывается по refresh из кабеля
RSpec.describe "Uploading photos", type: :system do
  let(:user)   { create(:user) }
  let(:folder) { create(:folder, user:, title: "Участок 1") }

  before { sign_in user }

  it "uploads a photo and shows it in the open folder without a reload" do
    visit new_media_item_path(folder_id: folder.id)
    attach_file "fileInput", Rails.root.join("spec/fixtures/files/pixel.jpg"), make_visible: true
    expect(page).to have_content("Все файлы загружены!")
    record_confirms(answer: false)
    click_button "Загрузить"

    expect(page).to have_current_path(folder_path(folder), ignore_query: true)
    expect(evaluate_script("window.confirms")).to eq([]) # после «Загрузить» форма сама уводит в папку — не спрашиваем
    expect(page).to have_content("1 файл загружаются в фоне")
    expect(page).to have_no_content("pixel")

    # Задачу выполняем здесь, а не в фоне: страница уже открыта и узнает о файле только из кабеля
    perform_enqueued_jobs(only: ProcessUploadsJob)

    expect(page).to have_content("pixel")
    expect(folder.media_items.count).to eq(1)
  end

  # Подменяет confirm: вопросы копятся в window.confirms. Turbo не перезагружает страницу — счётчик доживает до проверки
  def record_confirms(answer:)
    execute_script("window.confirms = []; window.confirm = (message) => { window.confirms.push(message); return #{answer} }")
  end

  # Загружены, но не сохранены кнопкой «Загрузить»: без отправки формы в папку не попадут — уходить только с согласия,
  # а ушли — файл сразу удаляется с сервера, а не ждёт ночной очистки
  it "asks before leaving with uploaded but unsaved files and deletes them on leave" do
    visit folder_path(folder)
    visit new_media_item_path(folder_id: folder.id)
    attach_file "fileInput", Rails.root.join("spec/fixtures/files/pixel.jpg"), make_visible: true
    expect(page).to have_content("Все файлы загружены!")
    blob = ActiveStorage::Blob.find_by!(filename: "pixel.jpg")

    record_confirms(answer: false)
    click_link "Назад"
    expect(evaluate_script("window.confirms")).to eq([ "Уйти, не сохранив загруженные файлы в папку?" ])
    expect(page).to have_current_path(new_media_item_path(folder_id: folder.id))

    record_confirms(answer: true)
    click_link "Назад"
    expect(page).to have_current_path(folder_path(folder))
    expect(evaluate_script("window.confirms").size).to eq(1)
    50.times { break unless ActiveStorage::Blob.exists?(blob.id); sleep 0.1 }
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
    expect(ActiveStorage::Blob.service.exist?(blob.key)).to be(false)
  end

  # Ctrl+клик по «Назад» — папка в новой вкладке, как у обычной ссылки. Со страницы никто не уходит:
  # ни назад по истории, ни вопроса, загруженное остаётся
  it "opens Назад in a new tab on Ctrl+click without leaving the page" do
    visit folder_path(folder)
    click_link title: "Загрузить файлы" # переход Turbo: в истории есть куда вернуться, «Назад» идёт по истории
    expect(page).to have_current_path(new_media_item_path(folder_id: folder.id))
    attach_file "fileInput", Rails.root.join("spec/fixtures/files/pixel.jpg"), make_visible: true
    expect(page).to have_content("Все файлы загружены!")
    record_confirms(answer: false)

    tab = window_opened_by { find_link("Назад").click(:control) }
    within_window(tab) { expect(page).to have_current_path(folder_path(folder)) }
    expect(page).to have_current_path(new_media_item_path(folder_id: folder.id))
    expect(evaluate_script("window.confirms")).to eq([])
    expect(page).to have_content("Все файлы загружены!")
  ensure
    tab&.close
  end

  # Вкладку перезагрузили или закрыли — Stimulus не вызывает disconnect, файл удаляется по pagehide
  it "deletes uploaded but unsaved files when the page is reloaded" do
    visit new_media_item_path(folder_id: folder.id)
    attach_file "fileInput", Rails.root.join("spec/fixtures/files/pixel.jpg"), make_visible: true
    expect(page).to have_content("Все файлы загружены!")
    blob = ActiveStorage::Blob.find_by!(filename: "pixel.jpg")

    execute_script("location.reload()")
    50.times { break unless ActiveStorage::Blob.exists?(blob.id); sleep 0.1 }
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
  end

  # У зоны transition: цвет доходит до конечного не сразу — ждём, пока перестанет меняться
  def settled(read)
    previous = nil
    20.times do
      current = read.call
      return current if current == previous
      previous = current
      sleep 0.1
    end
    previous
  end

  # Подсветка зоны, пока над ней несут файл. Цвет проверяем вычисленный: класс на месте ещё не значит,
  # что он виден, — его может перебить фон зоны с той же специфичностью
  it "highlights the drop zone while a file is dragged over it" do
    visit new_media_item_path(folder_id: folder.id)
    background = -> { page.evaluate_script("getComputedStyle(document.getElementById('dropZone')).backgroundColor") }
    drag = ->(type) { page.execute_script("document.getElementById('dropZone').dispatchEvent(new DragEvent('#{type}', { bubbles: true, cancelable: true, dataTransfer: new DataTransfer() }))") }
    idle = background.call

    drag.call("dragenter")
    expect(page).to have_css("#dropZone[data-dragover]")
    expect(settled(background)).to eq("rgb(246, 231, 253)") # --color-brand-soft

    drag.call("dragleave")
    expect(page).to have_no_css("#dropZone[data-dragover]")
    expect(settled(background)).to eq(idle)
  end

  # Файлы проверяются (MD5) по очереди, а грузятся, не дожидаясь остальных: все три доходят до сервера
  # с верной контрольной суммой (иначе сервис :local отказал бы в сохранении)
  it "checks and uploads several photos one after another" do
    files = %w[Ряд\ 1\ Куст\ 1 Ряд\ 1\ Куст\ 2 Ряд\ 1\ Куст\ 3].map do |name|
      Rails.root.join("tmp", "#{name}.jpg").tap { |path| FileUtils.cp(Rails.root.join("spec/fixtures/files/pixel.jpg"), path) }
    end

    visit new_media_item_path(folder_id: folder.id)
    attach_file "fileInput", files, make_visible: true
    expect(page).to have_content("Все файлы загружены!")
    click_button "Загрузить"

    expect(page).to have_content("3 файла загружаются в фоне")
    perform_enqueued_jobs(only: ProcessUploadsJob)
    expect(folder.media_items.joins(media_attachment: :blob).pluck("active_storage_blobs.filename"))
      .to match_array([ "Ряд 1 Куст 1.jpg", "Ряд 1 Куст 2.jpg", "Ряд 1 Куст 3.jpg" ])
  ensure
    files&.each { |path| FileUtils.rm_f(path) }
  end

  # «Назад» — переход Turbo без перезагрузки страницы: браузер сам ничего не обрывает, и без отмены
  # загрузка гигабайтов шла бы дальше невидимо и впустую (форму уже не отправить).
  # Отдача замедлена в Chrome: на любой машине уходим посреди загрузки, а не после неё
  it "stops uploading when the user leaves the page, asking once" do
    big = big_file
    network = page.driver.browser.network
    visit folder_path(folder)
    visit new_media_item_path(folder_id: folder.id)
    network.emulate_network_conditions(upload_throughput: 256.kilobytes)

    attach_file "fileInput", big, make_visible: true
    expect(page).to have_css("#preview-container div", text: /\AЗагрузка\s+\d+%\z/) # проверен, идёт загрузка
    record_confirms(answer: true) # «Назад» без истории — переход по ссылке, его видит и turbo:before-visit
    click_link "Назад"
    expect(page).to have_current_path(folder_path(folder))
    expect(evaluate_script("window.confirms")).to eq([ "Уйти со страницы и прервать загрузку?" ])

    upload = network.traffic.find { |exchange| exchange.request&.method == "PUT" }
    expect(upload).to be_present
    50.times { break unless upload.pending?; sleep 0.1 }
    expect(upload).not_to be_pending # оборван, а не идёт в фоне
    blob = ActiveStorage::Blob.find_by!(filename: "big_upload.zip") # запись есть, её уберёт ночная очистка
    expect(ActiveStorage::Blob.service.exist?(blob.key)).to be(false)
  ensure
    network&.emulate_network_conditions
    FileUtils.rm_f(big) if big
  end

  # Файл пропал с диска, пока ждал проверки: пользователю — понятная причина, а не текст браузера,
  # и блок ошибки растёт под текст, а не обрезает его
  it "explains in plain words when a file can no longer be read" do
    big = big_file
    gone = Rails.root.join("tmp", "Ряд 9 Куст 9.jpg").tap { |path| FileUtils.cp(Rails.root.join("spec/fixtures/files/pixel.jpg"), path) }

    visit new_media_item_path(folder_id: folder.id)
    attach_file "fileInput", [ big, gone ], make_visible: true
    FileUtils.rm_f(gone)

    error = find("#error-container div", text: "Ошибка загрузки \"Ряд 9 Куст 9.jpg\": не удалось прочитать файл", wait: 30)
    expect(error[:class].split).to include("min-h-16")
    expect(error[:class].split).not_to include("h-16")
    expect(page).to have_content("Загружено 1, с ошибкой 1", wait: 30)
  ensure
    FileUtils.rm_f(big) if big
    FileUtils.rm_f(gone) if gone
  end

  it "keeps uploading when the user changes their mind about leaving" do
    big = big_file
    network = page.driver.browser.network
    visit folder_path(folder)
    visit new_media_item_path(folder_id: folder.id)
    network.emulate_network_conditions(upload_throughput: 256.kilobytes) # к клику загрузка точно не кончится

    attach_file "fileInput", big, make_visible: true
    expect(page).to have_css("#preview-container div", text: /\AЗагрузка\s+\d+%\z/)
    expect(page).to have_no_css("#preview-container img[alt='ZIP архив']") # пока идёт загрузка, статус не ложится на подпись плитки
    expect(page).to have_css("#preview-container img[src='/file-archive.png'][alt='']") # а что это архив, видно по белой иконке
    dismiss_confirm { click_link "Назад" }
    network.emulate_network_conditions

    expect(page).to have_content("Все файлы загружены!", wait: 30)
    expect(page).to have_css("#preview-container img[alt='ZIP архив']") # загружен — фиолетовая иконка с размером вернулась
    expect(page).to have_no_css("#preview-container img[src='/file-archive.png'][alt='']")
    expect(page).to have_current_path(new_media_item_path(folder_id: folder.id))
    expect(ActiveStorage::Blob.find_by(filename: "big_upload.zip").byte_size).to eq(64.megabytes)
  ensure
    network&.emulate_network_conditions
    FileUtils.rm_f(big) if big
  end

  def big_file
    Rails.root.join("tmp", "big_upload.zip").tap do |path|
      File.open(path, "wb") { |f| 64.times { f.write(Random.bytes(1.megabyte)) } }
    end
  end
end
