require "rails_helper"

RSpec.describe "ActiveStorage file access", type: :request do
  let(:user)       { create(:user) }
  let(:other_user) { create(:user) }
  let(:media_item) { create(:media_item, :with_image, folder: create(:folder, user:)) }
  let(:blob)       { media_item.media.blob }

  context "when not authenticated" do
    it "does not serve the file" do
      get rails_blob_path(blob)
      expect(response).to have_http_status(:unauthorized) # не html, поэтому Devise отвечает 401, а не редиректом
    end
  end

  context "when authenticated as the owner" do
    before { sign_in user }

    it "serves the file via redirect" do
      get rails_blob_path(blob)
      expect(response).to redirect_to(%r{/rails/active_storage/disk/})
    end

    it "serves the file via proxy" do
      get rails_storage_proxy_path(blob)
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(blob.download)
    end
  end

  context "when authenticated as another user" do
    before { sign_in other_user }

    it "returns 404 for the original" do
      get rails_blob_path(blob)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for the proxied original" do
      get rails_storage_proxy_path(blob)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a variant without processing it" do
      # Поддельный JPEG из фабрики vips обработать не может: дойди дело до генерации превью, был бы Vips::Error
      get rails_representation_path(blob.variant(resize_to_limit: [ 132, 88 ]))
      expect(response).to have_http_status(:not_found)
    end

    it "serves a blob shared with their own demo copy" do
      copy = create(:media_item, folder: create(:folder, user: other_user))
      copy.media.attach(blob)

      get rails_blob_path(blob)
      expect(response).to redirect_to(%r{/rails/active_storage/disk/})
    end
  end
end
