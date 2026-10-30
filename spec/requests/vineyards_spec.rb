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
          bush_spacing: 1.5,
          bushes_per_row: "[10,10,10,10,10]"
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

      it "enqueues GenerateRowsAndBushesJob with parsed counts" do
        expect {
          post vineyards_path, params: valid_params
        }.to have_enqueued_job(GenerateRowsAndBushesJob).with(kind_of(Integer), [ 10, 10, 10, 10, 10 ])
      end

      it "does not create when bushes_per_row was not calculated" do
        params = valid_params.deep_merge(vineyard: { bushes_per_row: "[]" })
        expect {
          post vineyards_path, params:
        }.not_to change(Vineyard, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Не удалось рассчитать ряды и кусты")
      end

      it "does not create with invalid params" do
        expect {
          post vineyards_path, params: { vineyard: { name: "" } }
        }.not_to change(Vineyard, :count)
      end
    end
  end

  describe "PATCH /vineyards/:id" do
    before { sign_in user }

    context "when only the name changes" do
      it "updates without regenerating rows" do
        expect {
          patch vineyard_path(vineyard), params: { vineyard: { name: "Новое имя", bushes_per_row: "[]" } }
        }.not_to have_enqueued_job(RegenerateRowsAndBushesJob)
        expect(vineyard.reload.name).to eq("Новое имя")
        expect(response).to redirect_to(vineyard_path(vineyard))
      end
    end

    context "when the layout changes with a valid bushes_per_row" do
      it "enqueues RegenerateRowsAndBushesJob with parsed counts" do
        expect {
          patch vineyard_path(vineyard), params: { vineyard: { row_spacing: 2.8, bushes_per_row: "[3,4]" } }
        }.to have_enqueued_job(RegenerateRowsAndBushesJob).with(vineyard.id, [ 3, 4 ])
        expect(response).to redirect_to(vineyard_path(vineyard))
      end
    end

    context "when the layout changes but bushes_per_row is empty" do
      it "rejects the update and keeps rows" do
        old_spacing = vineyard.row_spacing
        expect {
          patch vineyard_path(vineyard), params: { vineyard: { row_spacing: 2.8, bushes_per_row: "[]" } }
        }.not_to have_enqueued_job(RegenerateRowsAndBushesJob)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(vineyard.reload.row_spacing).to eq(old_spacing)
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

      it "subscribes to the vineyard's stats refreshes" do
        get stats_vineyard_path(vineyard)
        expect(response.body).to include("turbo-cable-stream-source")
        expect(response.body).to include(Turbo::StreamsChannel.signed_stream_name([ vineyard, :stats ]))
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

  describe "GET /vineyards/:id/rows" do
    before { sign_in user }

    it "lists only rows with free bushes, labelled with the free count" do
      full_row = create(:row, vineyard:, row_number: 1)
      open_row = create(:row, vineyard:, row_number: 2)
      taken = create(:bush, vineyard:, row: full_row, bush_number: 1)
      create(:bush, vineyard:, row: open_row, bush_number: 1)
      create(:media_item, folder: create(:folder, user:), bush: taken)

      get rows_vineyard_path(vineyard, format: :json)
      expect(JSON.parse(response.body)).to eq([ { "id" => open_row.id, "label" => "Ряд 2 (1 свободный куст)" } ])
    end
  end

  describe "GET /vineyards/:id/heatmap" do
    it "returns current bush diagnoses to the owner" do
      sign_in user
      row  = create(:row, vineyard:, row_number: 1)
      item = create(:media_item, bush: create(:bush, vineyard:, row:, bush_number: 2), ai_class_id: 3)

      get heatmap_vineyard_path(vineyard, format: :json)
      expect(JSON.parse(response.body)).to eq("1-2" => [ item.id, 3 ])
    end

    it "denies another user" do
      sign_in other_user
      get heatmap_vineyard_path(vineyard, format: :json)
      expect(response).not_to have_http_status(:ok)
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

      it "subscribes to the user's total stats refreshes" do
        get total_stats_vineyards_path
        expect(response.body).to include(Turbo::StreamsChannel.signed_stream_name([ user, :stats ]))
      end
    end
  end
end
