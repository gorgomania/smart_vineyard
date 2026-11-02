require "rails_helper"

# Каскад виноградник → ряд → куст в браузере: Stimulus-контроллер bush-select подгружает ряды и кусты
# из JSON по выбору и показывает только свободные
RSpec.describe "Attaching a photo to a bush", type: :system do
  let(:user)       { create(:user) }
  let(:folder)     { create(:folder, user:) }
  let(:media_item) { create(:media_item, :with_image, folder:) }
  let(:vineyard)   { create(:vineyard, user:, name: "Северный") }
  let(:row)        { create(:row, vineyard:, row_number: 3) }

  before { sign_in user }

  it "loads rows and free bushes for the chosen vineyard and attaches the photo" do
    create(:bush, vineyard:, row:, bush_number: 1).tap { |taken| create(:media_item, folder:, bush: taken) }
    free = create(:bush, vineyard:, row:, bush_number: 2)

    visit attach_media_item_path(media_item)
    expect(page).to have_no_select("row_id")

    select "Северный", from: "vineyard_id"
    select "Ряд 3 (1 свободный куст)", from: "row_id"

    expect(page).to have_select("bush_id", options: [ "- Выберите куст -", "Куст 2" ])
    select "Куст 2", from: "bush_id"
    click_button "Прикрепить"

    expect(page).to have_content("Файл успешно прикреплен к кусту")
    expect(media_item.reload.bush).to eq(free)
  end
end
