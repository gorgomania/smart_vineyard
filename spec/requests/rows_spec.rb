require "rails_helper"

RSpec.describe "Rows", type: :request do
  let(:user)    { create(:user) }
  let(:vineyard) { create(:vineyard, user:) }
  let(:row)     { create(:row, vineyard:, row_number: 1) }

  describe "GET /rows/:id/bushes" do
    context "when not authenticated" do
      it "redirects to login" do
        get bushes_row_path(row)
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated as owner" do
      before { sign_in user }

      it "returns JSON with bushes" do
        create(:bush, vineyard:, row:, bush_number: 1)
        create(:bush, vineyard:, row:, bush_number: 2)
        get bushes_row_path(row)
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/json")
        json = JSON.parse(response.body)
        expect(json.length).to eq(2)
        expect(json.first).to include("id", "bush_number")
      end

      it "returns empty array when row has no bushes" do
        get bushes_row_path(row)
        expect(JSON.parse(response.body)).to eq([])
      end
    end

    context "when authenticated as another user" do
      before { sign_in create(:user) }

      it "redirects with access denied" do
        get bushes_row_path(row)
        expect(response).to redirect_to(folders_path)
      end
    end
  end
end
