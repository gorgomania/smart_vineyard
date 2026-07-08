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

    context "when another user tries to delete" do
      before { sign_in other_user }

      it "redirects with access denied" do
        delete folder_path(folder)
        expect(response).to redirect_to(folders_path)
      end
    end
  end

  describe "POST /folders/:id/attach_to_vineyard" do
    before { sign_in user }

    it "attaches folder to vineyard and enqueues job" do
      vineyard = create(:vineyard, user:)
      expect {
        post attach_to_vineyard_folder_path(folder), params: { vineyard_id: vineyard.id }
      }.to have_enqueued_job(DistributeFolderToBushesJob)
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
      }.to have_enqueued_job(DistributeFolderToBushesJob)
      expect(folder.reload.vineyard_id).to be_nil
    end
  end
end
