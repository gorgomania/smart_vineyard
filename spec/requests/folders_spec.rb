require "rails_helper"

RSpec.describe "Folders", type: :request do
  let(:user)       { create(:user) }
  let(:other_user) { create(:user) }
  let(:folder)     { create(:folder, user:, title: "My Folder") }

  describe "GET /folders" do
    context "when not authenticated" do
      it "redirects to login" do
        get folders_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated without search" do
      before { sign_in user }

      it "redirects to root folder" do
        get folders_path
        expect(response).to redirect_to(%r{/folders/\d+})
      end
    end

    context "when authenticated with search" do
      before { sign_in user }

      it "returns 200" do
        get folders_path, params: { folders: { title: "test" } }
        expect(response).to have_http_status(:ok)
      end

      it "treats % and _ in the query as plain characters" do
        create(:folder, user:, title: "100% done")
        create(:folder, user:, title: "plan_2026")
        create(:folder, user:, title: "plan-2026")

        get folders_path, params: { folders: { title: "%" } }
        expect(response.body).to include("100% done")
        expect(response.body).not_to include("plan_2026", "plan-2026")

        get folders_path, params: { folders: { title: "plan_" } }
        expect(response.body).to include("plan_2026")
        expect(response.body).not_to include("plan-2026")
      end
    end
  end

  describe "GET /folders/:id" do
    context "when not authenticated" do
      it "redirects to login" do
        get folder_path(folder)
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated as owner" do
      before { sign_in user }

      it "returns 200" do
        get folder_path(folder)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when authenticated as another user" do
      before { sign_in other_user }

      it "redirects with access denied" do
        get folder_path(folder)
        expect(response).to redirect_to(folders_path)
      end
    end
  end

  describe "POST /folders" do
    before { sign_in user }

    let(:root) { create(:folder, user:, title: "Root") }
    let(:valid_params) { { folders: { title: "New Folder", parent_id: root.id } } }

    it "creates a folder and redirects" do
      root # создаём заранее чтобы не учитывался в change
      expect {
        post folders_path, params: valid_params
      }.to change(Folder, :count).by(1)
      expect(response).to redirect_to(folder_path(root, page: "-2"))
    end

    it "renders new with error on blank title" do
      post folders_path, params: { folders: { title: "", parent_id: root.id } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    # Форма при ошибке открывается с тем, что ввели, и поле подсвечено — а не пустой
    it "keeps the typed title and highlights the field on error" do
      post folders_path, params: { folders: { title: "Слишком длинное имя", parent_id: root.id } }

      field = response.parsed_body.at_css("form[method='post'][action='#{folders_path}'] input[name='folders[title]']")
      expect(field["value"]).to eq("Слишком длинное имя")
      expect(field["class"].split).to include("!border-danger")
    end

    it "does not create a top-level folder without a parent" do
      expect {
        post folders_path, params: { folders: { title: "Orphan", parent_id: "" } }
      }.not_to change(Folder, :count)
      expect(response).to redirect_to(folders_path)
    end

    it "does not create a folder inside someone else's folder" do
      foreign = create(:folder, user: other_user)
      expect {
        post folders_path, params: { folders: { title: "Intruder", parent_id: foreign.id } }
      }.not_to change(Folder, :count)
    end
  end

  describe "root folder" do
    before { sign_in user }

    it "is created on the first visit" do
      expect { get folders_path }.to change { user.folders.where(parent_id: nil).count }.from(0).to(1)
    end

    it "has no delete button in search results, unlike nested folders" do
      root = create(:folder, user:, title: "Root")
      child = create(:folder, user:, title: "Rootstock", parent: root)

      get folders_path(folders: { title: "Root" })

      delete_form = ->(f) { %(action="#{ERB::Util.h(folder_path(f.id, page: 1, search_query: 'Root'))}") }
      expect(response.body).to include(ERB::Util.h(edit_folder_path(root.id, page: 1, search_query: "Root")))
      expect(response.body).not_to include(delete_form.(root))
      expect(response.body).to include(delete_form.(child))
    end

    it "is still found after being renamed" do
      root = create(:folder, user:, title: "Root")
      root.update!(title: "Мои фото")

      expect { get folders_path }.not_to change(Folder, :count)
      expect(response).to redirect_to(folder_path(root))
    end
  end

  describe "PATCH /folders/:id" do
    before { sign_in user }

    let(:root)  { create(:folder, user:, title: "Root") }
    let(:child) { create(:folder, user:, title: "Child", parent: root) }

    it "updates the folder title" do
      patch folder_path(child), params: { folders: { title: "Renamed" } }
      expect(child.reload.title).to eq("Renamed")
    end

    it "renders edit on blank title" do
      patch folder_path(child), params: { folders: { title: "" } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "keeps the typed title and highlights the field on error" do
      create(:folder, user:, title: "Занято", parent: root)
      patch folder_path(child), params: { folders: { title: "Занято" } }

      field = response.parsed_body.at_css("form[action='#{folder_path(child)}'] input[name='folders[title]']")
      expect(field["value"]).to eq("Занято")
      expect(field["class"].split).to include("!border-danger")
    end
  end

  describe "DELETE /folders/:id" do
    before { sign_in user }

    let(:root)   { create(:folder, user:, title: "Root") }
    let(:folder) { create(:folder, user:, title: "My Folder", parent: root) }

    it "does not delete the root folder" do
      root
      expect { delete folder_path(root) }.not_to change(Folder, :count)
      expect(response).to redirect_to(folders_path)
    end

    it "destroys the folder" do
      folder
      expect {
        delete folder_path(folder)
      }.to change(Folder, :count).by(-1)
    end

    it "redirects after destroy" do
      delete folder_path(folder)
      expect(response).to be_redirect
    end

    it "deletes nested folders and files at once and purges files in the background" do
      nested = create(:folder, user:, parent: folder, title: "Nested")
      item = create(:media_item, :with_image, folder: nested)

      expect {
        delete folder_path(folder)
      }.to change(Folder, :count).by(-2)
        .and change(MediaItem, :count).by(-1)
        .and have_enqueued_job(PurgeUnattachedBlobsJob).with([ item.media.blob.id ])
    end

    context "when another user tries to delete" do
      before { sign_in other_user }

      it "redirects with access denied" do
        delete folder_path(folder)
        expect(response).to redirect_to(folders_path)
      end

      it "does not delete anything" do
        folder
        expect { delete folder_path(folder) }.not_to change(Folder, :count)
      end
    end
  end

  describe "GET /folders/:id" do
    before { sign_in user }

    it "subscribes to folder refreshes and morphs the page on refresh" do
      get folder_path(folder)

      expect(response.body).to include("<turbo-cable-stream-source")
      expect(response.body).to include('<meta name="turbo-refresh-method" content="morph">')
      expect(response.body).to include('<meta name="turbo-refresh-scroll" content="preserve">')
    end

    it "keeps thumbnails morphable, so a refresh that shifts files between cards doesn't stack two images in one" do
      create(:media_item, :with_image, folder:)

      get folder_path(folder)

      expect(response.body).to include("animate-pulse")
      expect(response.body).not_to include("data-turbo-permanent")
    end
  end

  describe "GET /folders/:id/attach" do
    before { sign_in user }

    it "offers only vineyards that are not being deleted" do
      create(:vineyard, user:, name: "Живой")
      create(:vineyard, user:, name: "Удаляемый", deleted_at: Time.current)

      get attach_folder_path(folder)

      expect(response.body).to include("Живой")
      expect(response.body).not_to include("Удаляемый")
    end

    it "hides vineyards already taken by another folder" do
      create(:vineyard, user:, name: "Свободный")
      create(:folder, user:, title: "Другая", vineyard: create(:vineyard, user:, name: "Занятый"))

      get attach_folder_path(folder)

      expect(response.body).to include("Свободный")
      expect(response.body).not_to include("Занятый")
    end
  end

  describe "GET /folders/:id/edit_attach" do
    before { sign_in user }

    it "offers the folder's own vineyard but not ones taken by other folders" do
      folder.update!(vineyard: create(:vineyard, user:, name: "Свой"))
      create(:folder, user:, title: "Другая", vineyard: create(:vineyard, user:, name: "Занятый"))

      get edit_attach_folder_path(folder)

      expect(response.body).to include("Свой")
      expect(response.body).not_to include("Занятый")
    end
  end

  describe "POST /folders/:id/attach_to_vineyard" do
    before { sign_in user }

    it "attaches folder to vineyard and enqueues job" do
      vineyard = create(:vineyard, user:)
      expect {
        post attach_to_vineyard_folder_path(folder), params: { vineyard_id: vineyard.id }
      }.to have_enqueued_job(DistributeMediaToBushesJob)
      expect(folder.reload.vineyard_id).to eq(vineyard.id)
    end

    it "does not attach the folder to another user's vineyard" do
      foreign = create(:vineyard, user: other_user)
      expect {
        post attach_to_vineyard_folder_path(folder), params: { vineyard_id: foreign.id }
      }.not_to have_enqueued_job(DistributeMediaToBushesJob)
      expect(response).to redirect_to(folders_path)
      expect(folder.reload.vineyard_id).to be_nil
    end

    it "does not attach another user's folder" do
      vineyard = create(:vineyard, user:)
      foreign = create(:folder, user: other_user)
      expect {
        post attach_to_vineyard_folder_path(foreign), params: { vineyard_id: vineyard.id }
      }.not_to have_enqueued_job(DistributeMediaToBushesJob)
      expect(response).to redirect_to(folders_path)
      expect(foreign.reload.vineyard_id).to be_nil
    end
  end

  describe "DELETE /folders/:id/detach_from_vineyard" do
    before { sign_in user }

    it "detaches folder from vineyard and enqueues job" do
      vineyard = create(:vineyard, user:)
      folder.update!(vineyard:)
      expect {
        delete detach_from_vineyard_folder_path(folder)
      }.to have_enqueued_job(DistributeMediaToBushesJob)
      expect(folder.reload.vineyard_id).to be_nil
    end
  end

  describe "GET /folders/select_page" do
    before { sign_in user }

    # Ссылка «Назад» без истории ведёт туда же, куда сам выбор страницы
    it "renders for search results, where there is no folder, with the back link to the search" do
      get select_page_folders_path(search_query: "Куст", range_start: 1, range_end: 3)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="#{folders_path(folders: { title: "Куст" })}"))
    end

    it "renders for a folder with the back link to the folder" do
      get select_page_folders_path(id: folder.id, range_start: 1, range_end: 3)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="#{folder_path(folder)}"))
    end
  end

  describe "GET /folders/:id pagination" do
    before { sign_in user }

    # 24 на странице: P01–P24 на первой, P25–P30 на второй. Время создания задаём явно: страницы
    # сортируются по created_at, а часы машины (например, WSL2) могут прыгнуть назад между созданиями
    let!(:children) do
      base = 1.day.ago # одна точка отсчёта: 1.day.ago на каждую папку снова читал бы прыгающие часы
      (1..30).map { |n| create(:folder, user:, parent: folder, title: format("P%02d", n), created_at: base + n.seconds) }
    end

    def shown_titles
      response.body.scan(/P\d\d/).uniq
    end

    [ "0", "-5", "abc" ].each do |page|
      it "shows the first page for page=#{page} instead of failing on a negative OFFSET" do
        get folder_path(folder, page:)
        expect(response).to have_http_status(:ok)
        expect(shown_titles).to include("P01")
      end
    end

    it "shows the last page for a page past the end" do
      get folder_path(folder, page: 99)
      expect(shown_titles).to include("P30")
    end

    it "keeps page=-2 meaning the page with the last folder" do
      get folder_path(folder, page: -2)
      expect(shown_titles).to include("P30")
    end

    it "keeps page=-1 meaning the page where just uploaded files start" do
      create_list(:media_item, 20, folder:)
      get folder_path(folder, page: -1, successfull_uploads_count: 20) # 30 папок: загруженные начинаются на 2-й
      expect(shown_titles).to include("P30")
    end

    it "falls back to the first page when page=-1 counts more uploads than there are items" do
      get folder_path(folder, page: -1, successfull_uploads_count: 500)
      expect(response).to have_http_status(:ok)
      expect(shown_titles).to include("P01")
    end

    it "shows the first page for page=-2 in a folder without subfolders" do
      empty = create(:folder, user:, parent: folder)
      get folder_path(empty, page: -2)
      expect(response).to have_http_status(:ok)
    end

    # У пачки из ZIP или демо-копии created_at общий: страницы делятся по id, иначе порядок одинаковых строк
    # не определён и файл мог попасть на две страницы, а другой ни на одну. Чётные записи переписываем —
    # их строки уезжают в конец таблицы, и физический порядок перестаёт совпадать с id
    it "pages through files with the same created_at in id order, each exactly once" do
      batch = create(:folder, user:, parent: folder)
      items = create_list(:media_item, 30, folder: batch)
      # Файл без вложения папка не показывает. Один общий блоб на всех, как у демо-копий
      blob = ActiveStorage::Blob.create_and_upload!(io: File.open(PIXEL_JPEG), filename: "pixel.jpg", content_type: "image/jpeg")
      ActiveStorage::Attachment.insert_all(items.map { |item| { name: "media", record_type: "MediaItem", record_id: item.id, blob_id: blob.id, created_at: Time.current } })
      MediaItem.where(id: items.map(&:id)).update_all(created_at: 1.day.ago.round)
      MediaItem.where(id: items.map(&:id).select(&:even?)).update_all(updated_at: Time.current)

      shown = (1..2).flat_map do |page|
        get folder_path(batch, page:)
        response.body.scan(%r{/media_items/(\d+)/edit}).flatten.uniq.map(&:to_i)
      end
      expect(shown).to eq(items.map(&:id).sort)
    end

    it "shows the first page of search results for page=0" do
      get folders_path(folders: { title: "P" }, page: 0)
      expect(response).to have_http_status(:ok)
      expect(shown_titles).to include("P01")
    end
  end

  describe "GET /folders/:id video previews" do
    before { sign_in user }

    def attach_video(item)
      item.media.attach(io: StringIO.new("fake mp4"), filename: "clip.mp4", content_type: "video/mp4")
    end

    # Готовое превью приходит в канал папки: одна подписка на папку, а не на каждое видео
    it "subscribes to the folder's preview stream once, however many videos it shows" do
      3.times { attach_video(create(:media_item, folder:)) }

      get folder_path(folder)
      expect(response.body.scan("<turbo-cable-stream-source").size).to eq(2) # refresh папки + превью
    end
  end

  describe "GET /folders/select_page range" do
    before { sign_in user }

    def page_options
      response.body.scan(/<option value="(\d+)">/).flatten.map(&:to_i)
    end

    # Диапазон приходит в параметрах: без ограничения range_end=100000000 строил бы сто миллионов <option>
    it "limits the range to the folder's real pages" do
      create_list(:folder, 50, user:, parent: folder) # 3 страницы по 24

      get select_page_folders_path(id: folder.id, range_start: -5, range_end: 100_000_000)
      expect(page_options).to eq([ 1, 2, 3 ])
    end

    it "limits the range to the pages of the search results" do
      30.times { |i| create(:folder, user:, parent: folder, title: "Куст #{i}") } # 2 страницы

      get select_page_folders_path(search_query: "Куст", range_start: 2, range_end: 100_000_000)
      expect(page_options).to eq([ 2 ])
    end
  end

  describe "flash on form pages" do
    # Уведомление Devise после входа — не ошибка: зелёное, а не красное
    it "shows a notice in the success style" do
      get new_folder_path(parent_id: folder.id)
      post user_session_path, params: { user: { email: user.email, password: "password123" } }
      follow_redirect!

      notice = response.body[/<div[^>]*>\s*Вход в систему выполнен/]
      expect(notice).to include("text-success")
      expect(notice).not_to include("text-danger")
    end
  end
end
