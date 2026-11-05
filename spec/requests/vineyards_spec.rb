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
        expect(response.body).to include("Страница не найдена")
      end
    end
  end

  # Форма шлёт вершины, а не готовый контур: vineyard[vertex_N_lat], vineyard[vertex_N_lng]
  def vertex_params(points)
    points.each_with_index.flat_map { |(lat, lng), i| [ [ "vertex_#{i}_lat", lat.to_s ], [ "vertex_#{i}_lng", lng.to_s ] ] }.to_h
  end

  # Прямоугольник ~79 × 56 м, 0.44 га
  let(:rectangle) { [ [ 44.744, 33.56 ], [ 44.744, 33.561 ], [ 44.7445, 33.561 ], [ 44.7445, 33.56 ] ] }
  let(:rectangle_layout) do
    points = (rectangle + [ rectangle.first ])
    VineyardLayout.new(points, side_index: 0, row_spacing: 2.5, bush_spacing: 1.5)
  end

  describe "POST /vineyards" do
    let(:valid_params) do
      { vineyard: { name: "Мой виноградник", row_spacing: 2.5, bush_spacing: 1.5, reference_side_index: 0 }.merge(vertex_params(rectangle)) }
    end

    context "when not authenticated" do
      it "redirects to login" do
        post vineyards_path, params: valid_params
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "creates a vineyard from the form vertices and redirects" do
        expect {
          post vineyards_path, params: valid_params
        }.to change(Vineyard, :count).by(1)
        expect(response).to redirect_to(vineyard_path(Vineyard.last))
        expect(Vineyard.last.polygon.exterior_ring.points.map { |p| [ p.y, p.x ] }).to eq(rectangle + [ rectangle.first ])
      end

      # Числа из браузера подложить можно — сервер их не берёт, а считает раскладку и площадь сам
      it "lays out rows on the server, ignoring bushes_per_row, area and totals from the client" do
        params = valid_params.deep_merge(vineyard: { bushes_per_row: "[50000000]", area_hectares: 0.01, total_rows: 1, total_bushes: 1 })
        expected = rectangle_layout.bushes_per_row

        expect {
          post vineyards_path, params:
        }.to have_enqueued_job(SyncRowsAndBushesJob).with(kind_of(Integer), expected)
        vineyard = Vineyard.last
        expect([ vineyard.total_rows, vineyard.total_bushes ]).to eq([ expected.size, expected.sum ])
        expect(vineyard.area_hectares).to eq(rectangle_layout.area_hectares.round(2))
      end

      it "ignores a ready-made polygon from the client" do
        params = { vineyard: valid_params[:vineyard].reject { |key, _| key.start_with?("vertex_") }
                                                    .merge(polygon: "POLYGON((33 44, 34 44, 34 45, 33 45, 33 44))") }
        expect { post vineyards_path, params: }.not_to change(Vineyard, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects a plot over the area limit, measured on the server" do
        huge = [ [ 44.59, 33.47 ], [ 44.59, 33.48 ], [ 44.60, 33.48 ], [ 44.60, 33.47 ] ] # ~87 га
        params = valid_params.deep_merge(vineyard: vertex_params(huge).merge(area_hectares: 1))
        expect { post vineyards_path, params: }.not_to change(Vineyard, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "reports when the rows cannot be laid out from the reference side" do
        params = valid_params.deep_merge(vineyard: { reference_side_index: 9 })
        expect { post vineyards_path, params: }.not_to change(Vineyard, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Не удалось разложить ряды")
      end

      # Номер вершины из имени параметра раньше задавал длину массива: vertex_1000000000 — гигабайты памяти
      it "handles a huge vertex number without allocating for it" do
        params = valid_params.deep_merge(vineyard: { "vertex_1000000000_lat" => "44.7445", "vertex_1000000000_lng" => "33.5605" })
        expect { post vineyards_path, params: }.to change(Vineyard, :count).by(1)
        expect(Vineyard.last.polygon.exterior_ring.points.size).to eq(6)
      end

      it "turns a degenerate polygon into a form error, not a 500" do
        same_point = Array.new(4) { [ 44.744, 33.56 ] }
        params = valid_params.deep_merge(vineyard: vertex_params(same_point))
        expect { post vineyards_path, params: }.not_to change(Vineyard, :count)
        expect(response).to have_http_status(:unprocessable_content)
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
      it "updates without regenerating rows, keeping the stored totals" do
        expect {
          patch vineyard_path(vineyard), params: { vineyard: { name: "Новое имя", total_rows: 999 } }
        }.not_to have_enqueued_job(SyncRowsAndBushesJob)
        expect(vineyard.reload.name).to eq("Новое имя")
        expect(vineyard.total_rows).to eq(5)
        expect(response).to redirect_to(vineyard_path(vineyard))
      end
    end

    context "when the layout changes" do
      it "lays out rows on the server and enqueues SyncRowsAndBushesJob" do
        expected = VineyardLayout.new(rectangle + [ rectangle.first ], side_index: 0, row_spacing: 2.8, bush_spacing: 1.5).bushes_per_row
        expect {
          patch vineyard_path(vineyard), params: { vineyard: { row_spacing: 2.8, bushes_per_row: "[3,4]" } }
        }.to have_enqueued_job(SyncRowsAndBushesJob).with(vineyard.id, expected)
        expect(vineyard.reload.total_bushes).to eq(expected.sum)
        expect(response).to redirect_to(vineyard_path(vineyard))
      end
    end

    context "when the new layout cannot be laid out" do
      it "rejects the update and keeps rows" do
        expect {
          patch vineyard_path(vineyard), params: { vineyard: { reference_side_index: 9 } }
        }.not_to have_enqueued_job(SyncRowsAndBushesJob)
        expect(response).to have_http_status(:unprocessable_content)
        expect(vineyard.reload.reference_side_index).to eq(0)
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

      it "passes diagnosis names and palette keys to the chart" do
        row = create(:row, vineyard:, row_number: 1)
        create(:media_item, bush: create(:bush, vineyard:, row:, bush_number: 1), ai_class_id: 3)
        create(:bush, vineyard:, row:, bush_number: 2)

        get stats_vineyard_path(vineyard)
        stats = JSON.parse(Nokogiri::HTML(response.body).at("[data-dashboard-charts-stats-value]")["data-dashboard-charts-stats-value"])
        expect(stats.slice("labels", "diagnoses", "data")).to eq(
          "labels" => [ "Листовой ожог", "Нет данных" ], "diagnoses" => [ "leaf-blight", "none" ], "data" => [ 1, 1 ]
        )
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

  describe "GET /vineyards/:id?bushes_vision=true" do
    it "shows the legend with diagnosis names and palette colors" do
      sign_in user
      get vineyard_path(vineyard, bushes_vision: true)
      MediaItem::DIAGNOSES.each_value do |diagnosis|
        expect(response.body).to include(diagnosis[:name], "var(--color-diag-#{diagnosis[:key]})")
      end
      expect(response.body).to include("Нет данных", "var(--color-diag-none)")
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
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq("error" => "В доступе отказано")
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

  describe "POST /vineyards/select_stats" do
    before { sign_in user }

    it "asks to choose a vineyard instead of failing when none is chosen" do
      post select_stats_vineyards_path, params: { vineyard_id: "" }
      expect(response).to redirect_to(select_stats_vineyards_path)
      expect(flash[:alert]).to eq("Выберите виноградник")
    end
  end

  describe "GET /vineyards/new and /vineyards/:id/edit" do
    before { sign_in user }

    # Общий шаблон _form: заголовок, кнопка и «Назад» зависят от того, новый ли виноградник
    it "renders the create form" do
      get new_vineyard_path
      expect(response.body).to include("Создание виноградника", 'value="Создать"')
      expect(response.body).to match(/<a[^>]*title="Назад"[^>]*href="#{vineyards_path}"/)
    end

    it "renders the edit form" do
      get edit_vineyard_path(vineyard)
      expect(response.body).to include("Редактирование", 'value="Сохранить"')
      expect(response.body).to match(/<a[^>]*title="Назад"[^>]*href="#{vineyard_path(vineyard)}"/)
    end
  end

  describe "GET /vineyards/:id/edit spacing" do
    before { sign_in user }

    # Карта подставит значения сама, но если она не загрузилась, форма не должна отправить 3.0/1.5
    # и пересобрать ряды с чужим шагом
    it "renders the saved row and bush spacing in the sliders" do
      vineyard.update_columns(row_spacing: 2.4, bush_spacing: 1.3)

      get edit_vineyard_path(vineyard)
      expect(response.body).to match(/<input[^>]*name="vineyard\[row_spacing\]"[^>]*value="2.4"/)
        .or match(/<input[^>]*value="2.4"[^>]*name="vineyard\[row_spacing\]"/)
      expect(response.body).to match(/<input[^>]*name="vineyard\[bush_spacing\]"[^>]*value="1.3"/)
        .or match(/<input[^>]*value="1.3"[^>]*name="vineyard\[bush_spacing\]"/)
      expect(response.body).to include(">2.4</span>").and include(">1.3</span>")
    end
  end
end
