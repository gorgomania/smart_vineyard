require "rails_helper"

RSpec.describe "ActiveStorage overrides", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user)       { create(:user) }
  let(:other_user) { create(:user) }

  def unattached_blob(owner_id)
    ActiveStorage::Blob.create_before_direct_upload!(
      filename: "photo.jpg", byte_size: 100, checksum: "abc", content_type: "image/jpeg",
      metadata: { "user_id" => owner_id }
    )
  end

  describe "POST /rails/active_storage/direct_uploads" do
    let(:params) do
      { blob: { filename: "photo.jpg", byte_size: 100, checksum: "abc", content_type: "image/jpeg", metadata: { "user_id" => other_user.id } } }
    end

    it "requires login" do
      post "/rails/active_storage/direct_uploads", params:, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates a blob owned by the current user, ignoring user_id from the client" do
      sign_in user
      post "/rails/active_storage/direct_uploads", params:, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["signed_id"]).to be_present
      expect(body.dig("direct_upload", "url")).to be_present
      expect(ActiveStorage::Blob.find_signed(body["signed_id"]).metadata["user_id"]).to eq(user.id)
    end

    # Лимиты формы (upload_controller.js) держит и сервер: скрипт в обход формы получает отказ, blob не создаётся
    {
      "a file over 1 GB" => { byte_size: 1.gigabyte + 1 },
      "an empty file" => { byte_size: 0 },
      "a non-numeric size" => { byte_size: "lots" },
      "neither an image, a video nor a ZIP" => { filename: "notes.exe", content_type: "application/x-msdownload" }
    }.each do |name, overrides|
      it "rejects #{name}" do
        sign_in user
        expect {
          post "/rails/active_storage/direct_uploads", params: { blob: params[:blob].merge(overrides) }, as: :json
        }.not_to change(ActiveStorage::Blob, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    it "accepts a 1 GB video and a ZIP whatever type the browser gave it" do
      sign_in user
      post "/rails/active_storage/direct_uploads", as: :json,
           params: { blob: params[:blob].merge(filename: "clip.mp4", content_type: "video/mp4", byte_size: 1.gigabyte) }
      expect(response).to have_http_status(:ok)

      post "/rails/active_storage/direct_uploads", as: :json,
           params: { blob: params[:blob].merge(filename: "Photos.ZIP", content_type: "application/x-zip-compressed") }
      expect(response).to have_http_status(:ok)
    end

    # Большой файл грузится дольше штатных 5 минут, а токен проверяется уже после приёма всего тела
    it "issues an upload URL that stays valid for a long upload" do
      sign_in user
      post "/rails/active_storage/direct_uploads", params:, as: :json
      token = URI(response.parsed_body.dig("direct_upload", "url")).path.split("/").last

      travel 90.minutes do
        expect(ActiveStorage.verifier.verified(token, purpose: :blob_token)).to be_present
      end
      travel 3.hours do
        expect(ActiveStorage.verifier.verified(token, purpose: :blob_token)).to be_nil
      end
    end
  end

  describe "DELETE /active_storage/blobs/:id" do
    before { sign_in user }

    it "purges the current user's unattached blob" do
      blob = unattached_blob(user.id)
      delete active_storage_blob_path(blob.signed_id)

      expect(response).to have_http_status(:ok)
      expect(ActiveStorage::Blob.exists?(blob.id)).to be false
    end

    it "refuses another user's blob" do
      blob = unattached_blob(other_user.id)
      delete active_storage_blob_path(blob.signed_id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ActiveStorage::Blob.exists?(blob.id)).to be true
    end

    it "refuses a blob that is already attached" do
      item = create(:media_item, :with_image, folder: create(:folder, user:))
      blob = item.media.blob
      blob.update!(metadata: blob.metadata.merge("user_id" => user.id))

      delete active_storage_blob_path(blob.signed_id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(item.reload.media).to be_attached
    end

    it "refuses an unknown or forged id" do
      delete active_storage_blob_path("forged")
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
