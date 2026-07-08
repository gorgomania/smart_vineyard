require "rails_helper"

RSpec.describe "Vineyards", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:vineyard) { create(:vineyard, user:) }

  describe "GET /vineyards" do
    context "when not authenticated" do
      it "redirects to login" do
        get vineyards_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns 200" do
        get vineyards_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET /vineyards/:id" do
    context "when not authenticated" do
      it "redirects to login" do
        get vineyard_path(vineyard)
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated as owner" do
      before { sign_in user }

      it "returns 200" do
        get vineyard_path(vineyard)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when authenticated as another user" do
      before { sign_in other_user }

      it "returns 404" do
        get vineyard_path(vineyard)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /vineyards" do
    let(:valid_params) do
      {
        vineyard: {
          name: "Мой виноградник",
          polygon: "POLYGON((33.47 44.59, 33.48 44.59, 33.48 44.60, 33.47 44.60, 33.47 44.59))",
          area_hectares: 1.5,
          total_rows: 5,
          total_bushes: 50,
          row_spacing: 2.5,
          bush_spacing: 1.5
        }
      }
    end

    context "when not authenticated" do
      it "redirects to login" do
        post vineyards_path, params: valid_params
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "creates a vineyard and redirects" do
        expect {
          post vineyards_path, params: valid_params
        }.to change(Vineyard, :count).by(1)
        expect(response).to redirect_to(vineyard_path(Vineyard.last))
      end

      it "does not create with invalid params" do
        expect {
          post vineyards_path, params: { vineyard: { name: "" } }
        }.not_to change(Vineyard, :count)
      end
    end
  end

  describe "DELETE /vineyards/:id" do
    context "when authenticated as owner" do
      before { sign_in user }

      it "soft-deletes the vineyard" do
        vineyard
        expect {
          delete vineyard_path(vineyard)
        }.not_to change(Vineyard, :count)
        expect(vineyard.reload.deleted_at).not_to be_nil
      end

      it "redirects to index" do
        delete vineyard_path(vineyard)
        expect(response).to redirect_to(vineyards_path)
      end
    end

    context "when authenticated as another user" do
      before { sign_in other_user }

      it "redirects with access denied" do
        delete vineyard_path(vineyard)
        expect(response).to redirect_to(folders_path)
      end

      it "does not soft-delete the vineyard" do
        delete vineyard_path(vineyard)
        expect(vineyard.reload.deleted_at).to be_nil
      end
    end
  end

  describe "GET /vineyards/:id/stats" do
    context "when authenticated as owner" do
      before { sign_in user }

      it "returns 200" do
        get stats_vineyard_path(vineyard)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when authenticated as another user" do
      before { sign_in other_user }

      it "redirects with access denied" do
        get stats_vineyard_path(vineyard)
        expect(response).to redirect_to(folders_path)
      end
    end
  end

  describe "GET /vineyards/total_stats" do
    context "when not authenticated" do
      it "redirects to login" do
        get total_stats_vineyards_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns 200" do
        get total_stats_vineyards_path
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
