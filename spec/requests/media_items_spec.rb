require "rails_helper"

RSpec.describe "MediaItems", type: :request do
  let(:user)       { create(:user) }
  let(:other_user) { create(:user) }
  let(:folder)     { create(:folder, user:) }
  let(:media_item) { create(:media_item, :with_image, folder:) }

  before do
    allow(GrapeClassifier).to receive(:class_names).and_return([])
  end

  describe "GET /media_items/:id" do
    context "when not authenticated" do
      it "redirects to login" do
        get media_item_path(media_item)
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated as owner" do
      before { sign_in user }

      it "returns 200" do
        get media_item_path(media_item)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when authenticated as another user" do
      before { sign_in other_user }

      it "redirects with access denied" do
        get media_item_path(media_item)
        expect(response).to redirect_to(folders_path)
      end
    end
  end

  describe "POST /media_items" do
    before { sign_in user }

    context "without any files" do
      it "redirects with alert" do
        post media_items_path, params: { media_item: { folder_id: folder.id } }
        expect(response).to redirect_to(new_media_item_path(folder_id: folder.id))
      end
    end

    context "with blob IDs" do
      it "enqueues AttachMediaJob and redirects" do
        expect {
          post media_items_path, params: {
            media_item: { folder_id: folder.id },
            signed_blob_ids: "id1,id2"
          }
        }.to have_enqueued_job(AttachMediaJob)
        expect(response).to redirect_to(folder_path(folder, page: "-1"))
      end
    end

    context "with ZIP archives uploaded via DirectUpload" do
      def zip_blob(owner_id, filename: "photos.zip")
        ActiveStorage::Blob.create_before_direct_upload!(
          filename:, byte_size: 22, checksum: "abc", content_type: "application/x-zip-compressed",
          metadata: { "user_id" => owner_id }
        )
      end

      it "enqueues ProcessZipJob with the user's archive blob" do
        blob = zip_blob(user.id)

        expect {
          post media_items_path, params: { media_item: { folder_id: folder.id }, signed_zip_ids: blob.signed_id }
        }.to have_enqueued_job(ProcessZipJob).with(folder, blob)
        expect(response).to redirect_to(folder_path(folder, page: "-1"))
      end

      it "ignores archives uploaded by someone else and non-zip blobs" do
        foreign = zip_blob(other_user.id)
        not_zip = zip_blob(user.id, filename: "photo.jpg")

        expect {
          post media_items_path, params: {
            media_item: { folder_id: folder.id }, signed_zip_ids: [ foreign.signed_id, not_zip.signed_id ].join(",")
          }
        }.not_to have_enqueued_job(ProcessZipJob)
        expect(response).to redirect_to(new_media_item_path(folder_id: folder.id))
      end
    end
  end

  describe "PATCH /media_items/:id" do
    let(:demo_user)   { create(:user) }
    let(:demo_folder) { create(:folder, user: demo_user) }
    let(:demo_item) do
      create(:media_item, folder: demo_folder).tap do |item|
        ActiveStorage::Attachment.create!(name: "media", record: item, blob: media_item.media.blob)
      end
    end

    before { sign_in demo_user }

    it "renames only the demo copy when the blob is shared with the master" do
      patch media_item_path(demo_item), params: { media_item: { filename: "renamed" } }

      expect(demo_item.reload.media.blob.filename.to_s).to eq("renamed.jpg")
      expect(media_item.reload.media.blob.filename.to_s).to eq("test.jpg")
    end
  end

  describe "DELETE /media_items/:id" do
    before { sign_in user }

    it "destroys the media item" do
      media_item
      expect {
        delete media_item_path(media_item)
      }.to change(MediaItem, :count).by(-1)
    end

    it "redirects to folder" do
      delete media_item_path(media_item)
      expect(response).to redirect_to(folder_path(folder, page: nil))
    end

    context "when another user tries to delete" do
      before { sign_in other_user }

      it "redirects with access denied" do
        delete media_item_path(media_item)
        expect(response).to redirect_to(folders_path)
      end
    end
  end

  describe "POST /media_items/:id/classify" do
    before { sign_in user }

    it "enqueues ClassifyMediaJob and redirects" do
      expect(ClassifyMediaJob).to receive(:perform_later).with(media_item.id)
      post classify_media_item_path(media_item)
      expect(response).to redirect_to(media_item_path(media_item))
    end
  end

  describe "POST /media_items/:id/attach_to_bush" do
    before { sign_in user }

    let(:vineyard) { create(:vineyard, user:) }
    let(:row)      { create(:row, vineyard:, row_number: 1) }
    let(:bush)     { create(:bush, vineyard:, row:, bush_number: 1) }

    it "attaches media item to bush and redirects" do
      post attach_to_bush_media_item_path(media_item), params: { bush_id: bush.id }
      expect(media_item.reload.bush_id).to eq(bush.id)
      expect(response).to redirect_to(media_item_path(media_item))
    end
  end

  describe "DELETE /media_items/:id/detach_from_bush" do
    before { sign_in user }

    it "detaches media item from bush and redirects" do
      row  = create(:row, vineyard: create(:vineyard, user:), row_number: 1)
      bush = create(:bush, vineyard: row.vineyard, row:, bush_number: 1)
      media_item.update!(bush:)

      delete detach_from_bush_media_item_path(media_item)
      expect(media_item.reload.bush_id).to be_nil
      expect(response).to redirect_to(media_item_path(media_item))
    end
  end
end
