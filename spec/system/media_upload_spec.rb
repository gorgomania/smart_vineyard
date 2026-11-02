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
end
