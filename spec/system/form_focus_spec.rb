require "rails_helper"

# Автофокус — только там, где страница существует ради этого поля. На переименовании текущее имя
# сразу выделено: новое набирается поверх, как в проводнике
RSpec.describe "Form focus", type: :system do
  let(:user)   { create(:user) }
  let(:parent) { create(:folder, user:, title: "Участок 1") }
  let!(:child) { create(:folder, user:, parent:, title: "Ряды 1–10") }

  before { sign_in user }

  # Форма, куда уйдёт поле в фокусе, и выделенный в нём текст. По форме, а не по name: у поиска в шапке
  # тоже folders[title]
  def focused_selection
    evaluate_script("(() => { const el = document.activeElement; return [ el.form?.getAttribute('action'), el.value.slice(el.selectionStart, el.selectionEnd) ] })()")
  end

  it "selects the folder name on a full page load" do
    visit edit_folder_path(child)
    expect(focused_selection).to eq([ folder_path(child), "Ряды 1–10" ])
  end

  # Переход Turbo без перезагрузки: фокус по autofocus ставит Turbo, а не браузер
  it "selects the folder name after a Turbo visit" do
    visit folder_path(parent)
    find_link(title: "Переименовать").click
    expect(page).to have_current_path(edit_folder_path(child), ignore_query: true)
    expect(focused_selection).to eq([ folder_path(child), "Ряды 1–10" ])
  end

  it "selects the file name without the extension" do
    item = create(:media_item, :with_named_image, folder: parent, image_filename: "Ряд 1 Куст 2.jpg")
    visit edit_media_item_path(item)
    expect(focused_selection).to eq([ media_item_path(item), "Ряд 1 Куст 2" ])
  end

  # Поиск — как адресная строка: в поле прошлый запрос, первый клик выделяет его целиком, второй ставит курсор.
  # Ушли из поля и вернулись кликом — снова целиком
  it "selects the search query on the first click and places the caret on the second" do
    visit folders_path(folders: { title: "Участок" })
    search = find("#folders_title")

    search.click
    expect(focused_selection.last).to eq("Участок")
    search.click
    expect(focused_selection.last).to eq("")

    find("body").click(x: 5, y: 5)
    search.click
    expect(focused_selection.last).to eq("Участок")
  end

  # На переименовании выделяет только autofocus: дальше клик ставит курсор, чтобы поправить имя
  it "places the caret on a click into the rename field after the initial selection" do
    visit edit_folder_path(child)
    expect(focused_selection.last).to eq("Ряды 1–10")
    find_field("Название").click
    expect(focused_selection.last).to eq("")
  end

  # При редактировании обычно правят границы на карте: клавиатура телефона не должна выезжать поверх неё
  it "focuses the vineyard name only when creating one" do
    vineyard = create(:vineyard, user:)
    visit edit_vineyard_path(vineyard)
    expect(page).to have_field("Название")
    expect(page).to have_no_css("input[autofocus]")

    visit new_vineyard_path
    expect(page).to have_css("input[name='vineyard[name]'][autofocus]")
  end

  it "does not focus email on the profile page" do
    visit edit_user_registration_path
    expect(page).to have_field("Email")
    expect(page).to have_no_css("input[autofocus]")
  end
end
