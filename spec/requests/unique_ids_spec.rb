require "rails_helper"

# id на странице должен быть один: по нему label находит своё поле, а скрипты — элемент. Поля поиска в шапке
# и формы папки называются одинаково (folders[title]) — если шапка появится на странице формы, id совпадут
RSpec.describe "Unique element ids", type: :request do
  let(:user)     { create(:user) }
  let(:root)     { create(:folder, user:, title: "Root") }
  let(:folder)   { create(:folder, user:, parent: root, title: "Участок 1") }
  let(:vineyard) { create(:vineyard, user:) }
  let(:item)     { create(:media_item, :with_image, folder:) }

  before { sign_in user }

  {
    "folder search"        => -> { folders_path(folders: { title: "Уч" }) },
    "folder"               => -> { folder_path(folder) },
    "new folder"           => -> { new_folder_path(parent_id: folder.id) },
    "edit folder"          => -> { edit_folder_path(folder) },
    "attach folder"        => -> { attach_folder_path(folder) },
    "upload"               => -> { new_media_item_path(folder_id: folder.id) },
    "file"                 => -> { media_item_path(item) },
    "edit file"            => -> { edit_media_item_path(item) },
    "vineyards"            => -> { vineyards_path },
    "new vineyard"         => -> { new_vineyard_path },
    "edit vineyard"        => -> { edit_vineyard_path(vineyard) },
    "vineyard"             => -> { vineyard_path(vineyard) },
    "total stats"          => -> { total_stats_vineyards_path },
    "profile"              => -> { users_path },
    "edit profile"         => -> { edit_user_registration_path },
    "delete profile"       => -> { delete_user_registration_path }
  }.each do |name, path|
    it "has no repeated ids on the #{name} page" do
      get instance_exec(&path)
      expect(response).to have_http_status(:ok)
      ids = response.parsed_body.css("[id]").map { |el| el["id"] }
      expect(ids.tally.select { |_, count| count > 1 }.keys).to eq([])
    end
  end
end
