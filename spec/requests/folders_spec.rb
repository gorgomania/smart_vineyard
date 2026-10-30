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
end
