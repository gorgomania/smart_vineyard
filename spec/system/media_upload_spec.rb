require "rails_helper"

# Полный путь загрузки в браузере: Stimulus-контроллер upload грузит файл через DirectUpload, форма уходит
# с signed id, AttachMediaJob создаёт файл, а открытая страница папки сама перерисовывается по refresh из кабеля
RSpec.describe "Uploading photos", type: :system do
  let(:user)   { create(:user) }
  let(:folder) { create(:folder, user:, title: "Участок 1") }

  before { sign_in user }

  it "uploads a photo and shows it in the open folder without a reload" do
    visit new_media_item_path(folder_id: folder.id)
    attach_file "fileInput", Rails.root.join("spec/fixtures/files/pixel.jpg"), make_visible: true
    click_button "Загрузить"

    expect(page).to have_current_path(folder_path(folder), ignore_query: true)
    expect(page).to have_content("1 файл загружаются в фоне")
    expect(page).to have_no_content("pixel")

    # Задачу выполняем здесь, а не в фоне: страница уже открыта и узнает о файле только из кабеля
    perform_enqueued_jobs(only: AttachMediaJob)

    expect(page).to have_content("pixel")
    expect(folder.media_items.count).to eq(1)
  end

  # Файлы проверяются (MD5) по очереди, а грузятся, не дожидаясь остальных: все три доходят до сервера
  # с верной контрольной суммой (иначе сервис :local отказал бы в сохранении)
  it "checks and uploads several photos one after another" do
    files = %w[Ряд\ 1\ Куст\ 1 Ряд\ 1\ Куст\ 2 Ряд\ 1\ Куст\ 3].map do |name|
      Rails.root.join("tmp", "#{name}.jpg").tap { |path| FileUtils.cp(Rails.root.join("spec/fixtures/files/pixel.jpg"), path) }
    end

    visit new_media_item_path(folder_id: folder.id)
    attach_file "fileInput", files, make_visible: true
    expect(page).to have_content("✅ Все файлы загружены!")
    click_button "Загрузить"

    expect(page).to have_content("3 файла загружаются в фоне")
    perform_enqueued_jobs(only: AttachMediaJob)
    expect(folder.media_items.joins(media_attachment: :blob).pluck("active_storage_blobs.filename"))
      .to match_array([ "Ряд 1 Куст 1.jpg", "Ряд 1 Куст 2.jpg", "Ряд 1 Куст 3.jpg" ])
  ensure
    files&.each { |path| FileUtils.rm_f(path) }
  end

  # «Назад» — переход Turbo без перезагрузки страницы: браузер сам ничего не обрывает, и без отмены
  # проверка и загрузка гигабайтов шли бы дальше невидимо и впустую (форму уже не отправить)
  it "stops checking and uploading when the user leaves the page" do
    big = Rails.root.join("tmp", "big_upload.zip")
    File.open(big, "wb") { |f| 64.times { f.write(Random.bytes(1.megabyte)) } }
    visit folder_path(folder)
    visit new_media_item_path(folder_id: folder.id)

    attach_file "fileInput", big, make_visible: true
    expect(page).to have_content(/Проверка|В очереди/)
    accept_confirm { click_link "Назад" }
    expect(page).to have_current_path(folder_path(folder))

    sleep 3 # за это время 64 МБ успели бы и проверить, и создать blob
    expect(ActiveStorage::Blob.where(filename: "big_upload.zip")).not_to exist
  ensure
    FileUtils.rm_f(big) if big
  end

  # Файл пропал с диска, пока ждал проверки: пользователю — понятная причина, а не текст браузера,
  # и блок ошибки растёт под текст, а не обрезает его
  it "explains in plain words when a file can no longer be read" do
    big = Rails.root.join("tmp", "big_upload.zip")
    File.open(big, "wb") { |f| 64.times { f.write(Random.bytes(1.megabyte)) } }
    gone = Rails.root.join("tmp", "Ряд 9 Куст 9.jpg").tap { |path| FileUtils.cp(Rails.root.join("spec/fixtures/files/pixel.jpg"), path) }

    visit new_media_item_path(folder_id: folder.id)
    attach_file "fileInput", [ big, gone ], make_visible: true
    FileUtils.rm_f(gone)

    error = find("#error-container div", text: "Ошибка загрузки \"Ряд 9 Куст 9.jpg\": не удалось прочитать файл", wait: 30)
    expect(error[:class].split).to include("min-h-16")
    expect(error[:class].split).not_to include("h-16")
    expect(page).to have_content("✅ Загружено 1, с ошибкой 1", wait: 30)
  ensure
    FileUtils.rm_f(big) if big
    FileUtils.rm_f(gone) if gone
  end

  it "keeps uploading when the user changes their mind about leaving" do
    big = Rails.root.join("tmp", "big_upload.zip")
    File.open(big, "wb") { |f| 64.times { f.write(Random.bytes(1.megabyte)) } }
    visit folder_path(folder)
    visit new_media_item_path(folder_id: folder.id)

    attach_file "fileInput", big, make_visible: true
    expect(page).to have_content(/Проверка|В очереди/)
    dismiss_confirm { click_link "Назад" }

    expect(page).to have_content("✅ Все файлы загружены!", wait: 30)
    expect(page).to have_current_path(new_media_item_path(folder_id: folder.id))
    expect(ActiveStorage::Blob.find_by(filename: "big_upload.zip").byte_size).to eq(64.megabytes)
  ensure
    FileUtils.rm_f(big) if big
  end
end
