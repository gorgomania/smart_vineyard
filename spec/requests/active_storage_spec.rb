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
