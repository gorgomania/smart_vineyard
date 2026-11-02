class VineyardsController < ApplicationController
  LAYOUT_ATTRIBUTES = %w[polygon row_spacing bush_spacing reference_side_index reference_vertex_is_first].freeze
  LAYOUT_NOT_CALCULATED_MESSAGE = "Не удалось разложить ряды: проверьте контур участка и опорную сторону".freeze
  # Вершин у участка столько не бывает; без лимита номер из имени параметра (vertex_N_lat) задавал бы объём разбора
  MAX_VERTICES = 100
  RGEO_FACTORY = RGeo::Geographic.spherical_factory(srid: 4326)

  def index
    @map_center, @map_zoom = initialize_map
    @mode = "index"
    @vineyards = policy_scope(Vineyard).active.for_index
    @vineyards_data = @vineyards.map do |v|
      {
        id: v.id,
        name: v.name,
        polygon: v.polygon.to_s,
        total_rows: v.total_rows,
        total_bushes: v.total_bushes,
        area: v.area_hectares.to_f,
        grape_variety: v.grape_variety
      }
    end
  end

  def show
    @map_center, @map_zoom = initialize_map
    @mode = "show"
    @vineyard = policy_scope(Vineyard.active).find_by(id: params[:id])
    return not_found if @vineyard.nil?
    authorize @vineyard
    # Диагнозы карта грузит сама с heatmap.json, когда подключится подписка на обновления
    @bushes_vision = params[:bushes_vision] == "true"
    @vineyard_data = {
      polygon: @vineyard.polygon.to_s,
      row_spacing: @vineyard.row_spacing.to_f,
      bush_spacing: @vineyard.bush_spacing.to_f,
      reference_side_index: @vineyard.reference_side_index,
      reference_vertex_is_first: @vineyard.reference_vertex_is_first
    }
  end

  def new
    @vineyard = current_user.vineyards.new
    setup_new_form_data
  end

  def create
    @vineyard = current_user.vineyards.build(vineyard_params_permit)
    bushes_per_row = calculate_layout(@vineyard)

    if bushes_per_row && @vineyard.save
      GenerateRowsAndBushesJob.perform_later(@vineyard.id, bushes_per_row)
      redirect_to @vineyard, notice: "Виноградник создан"
    else
      setup_new_form_data
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @vineyard = Vineyard.active.find(params[:id])
    authorize @vineyard
    setup_edit_form_data
  end

  def update
    @vineyard = Vineyard.active.find(params[:id])
    authorize @vineyard

    @vineyard.assign_attributes(vineyard_params_permit)
    # Ряды пересчитываем только при изменении геометрии и только если раскладка получилась:
    # пустая удалила бы все ряды и кусты
    layout_changed = @vineyard.changed.intersect?(LAYOUT_ATTRIBUTES)
    bushes_per_row = calculate_layout(@vineyard) if layout_changed

    if (!layout_changed || bushes_per_row) && @vineyard.save
      RegenerateRowsAndBushesJob.perform_later(@vineyard.id, bushes_per_row) if layout_changed
      redirect_to @vineyard, notice: "Виноградник обновлён"
    else
      setup_edit_form_data
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    vineyard = Vineyard.active.find(params[:id])
    authorize vineyard
    vineyard.soft_destroy
    redirect_to vineyards_path, notice: "Виноградник успешно удалён"
  end

  def stats
    @vineyard = Vineyard.active.find(params[:id])
    authorize @vineyard
    @stats_data = get_statistics(@vineyard)
  end

  def total_stats
    @vineyards = policy_scope(Vineyard).active
    @stats_data = get_statistics(@vineyards)
    @total = true
    render "stats"
  end

  def select_stats
    if request.get?
      vineyards = policy_scope(Vineyard).active.order(:name)
      @options = [ [ "Все виноградники", "all" ] ]
      vineyards.each do |v|
        @options << [ v.name, v.id ]
      end
    else
      if params[:vineyard_id] == "all"
        redirect_to total_stats_vineyards_path
      elsif params[:vineyard_id].present?
        redirect_to stats_vineyard_path(params[:vineyard_id])
      else
        # Без выбора stats_vineyard_path(nil) не строится — было 500
        redirect_to select_stats_vineyards_path, alert: "Выберите виноградник"
      end
    end
  end

  def bushes_per_row
    vineyard = Vineyard.active.find(params[:id])
    authorize vineyard
    data = vineyard.rows.order(:row_number).pluck(Arel.sql("( SELECT COUNT(*) FROM bushes WHERE bushes.row_id = rows.id )"))
    render json: data
  end

  # Свежие диагнозы для тепловой карты: она перечитывает их, когда подписка на обновления подключилась
  def heatmap
    vineyard = Vineyard.active.find(params[:id])
    authorize vineyard
    render json: vineyard.bushes_diagnoses
  end

  def rows
    vineyard = Vineyard.active.find(params[:id])
    authorize vineyard
    rows = Row.with_free_bushes(vineyard, keep_bush_id: params[:keep_bush_id])

    render json: rows.map { |row, free_count| { id: row.id, label: row.free_bushes_label(free_count) } }
  end

  private

  def setup_new_form_data
    @map_center, @map_zoom = initialize_map
    @mode = "new"
    @vineyard_data = @vineyard.polygon.present? ? {
      polygon: @vineyard.polygon.to_s,
      row_spacing: @vineyard.row_spacing.to_f,
      bush_spacing: @vineyard.bush_spacing.to_f,
      reference_side_index: @vineyard.reference_side_index,
      reference_vertex_is_first: @vineyard.reference_vertex_is_first
    } : nil
    @vineyards = policy_scope(Vineyard).active.for_index
    @vineyards_data = vineyard_map_data(@vineyards)
  end

  def setup_edit_form_data
    @map_center, @map_zoom = initialize_map
    @mode = "edit"
    @vineyard_data = {
      polygon: @vineyard.polygon.to_s,
      row_spacing: @vineyard.row_spacing.to_f,
      bush_spacing: @vineyard.bush_spacing.to_f,
      reference_side_index: @vineyard.reference_side_index,
      reference_vertex_is_first: @vineyard.reference_vertex_is_first
    }
    @vineyards = policy_scope(Vineyard).active.for_index.where.not(id: @vineyard.id)
    @vineyards_data = vineyard_map_data(@vineyards)
  end

  def vineyard_map_data(vineyards)
    vineyards.map do |v|
      {
        id: v.id,
        name: v.name,
        polygon: v.polygon.to_s,
        total_rows: v.total_rows,
        total_bushes: v.total_bushes,
        area: v.area_hectares.to_f,
        grape_variety: v.grape_variety
      }
    end
  end

  # Раскладку, площадь и итоги считает сервер (VineyardLayout) — так же, как карта в форме, но числам из браузера
  # не верим: подложенные bushes_per_row или площадь создали бы миллионы кустов в обход «не больше 10 га».
  # Возвращает bushes_per_row или nil, тогда ошибки уже в vineyard.errors
  def calculate_layout(vineyard)
    vineyard.validate
    # Эти поля считаются здесь, а не вводятся: их ошибки до расчёта только путают
    %i[area_hectares total_rows total_bushes].each { |attribute| vineyard.errors.delete(attribute) }
    # Без контура или с шагом вне допустимого раскладывать нечего (шаг 0 — бесконечный цикл), ошибка уже есть
    return if vineyard.polygon.nil? || vineyard.errors.include?(:row_spacing) || vineyard.errors.include?(:bush_spacing)

    layout = VineyardLayout.for(vineyard)
    bushes_per_row = layout.bushes_per_row
    if bushes_per_row.none?(&:positive?)
      vineyard.errors.add(:base, LAYOUT_NOT_CALCULATED_MESSAGE)
      return
    end

    vineyard.assign_attributes(area_hectares: layout.area_hectares.round(2),
                               total_rows: bushes_per_row.size, total_bushes: bushes_per_row.sum)
    bushes_per_row
  end

  # Контур собирается из вершин формы (vineyard[vertex_N_lat], vineyard[vertex_N_lng]) по возрастанию N.
  # Площадь, ряды и кусты из формы не принимаются — их считает calculate_layout
  def vineyard_params_permit
    # Только из вершин: присланный готовым контур обошёл бы и лимит вершин, и проверку WKT
    params[:vineyard].delete(:polygon)
    vertices = {}
    params[:vineyard].each do |key, value|
      match = key.to_s.match(/\Avertex_(\d+)_(lat|lng)\z/)
      next unless match

      (vertices[match[1].to_i] ||= {})[match[2].to_sym] = Float(value, exception: false)
    end

    points = vertices.sort.map(&:last).select { |v| v[:lat]&.finite? && v[:lng]&.finite? }
    if points.size.between?(3, MAX_VERTICES)
      # WKT — «lng lat», контур замкнут
      wkt = "POLYGON((#{(points + [ points.first ]).map { |v| "#{v[:lng]} #{v[:lat]}" }.join(", ")}))"
      params[:vineyard][:polygon] = wkt if valid_polygon?(wkt)
    end

    params.require(:vineyard).permit(
      :name, :grape_variety, :planting_year, :row_spacing, :bush_spacing,
      :polygon, :reference_side_index, :reference_vertex_is_first
    )
  end

  # Вырожденный контур (совпадающие вершины) RGeo не примет: при присваивании это было бы 500, а не ошибка формы
  def valid_polygon?(wkt)
    RGEO_FACTORY.parse_wkt(wkt)
    true
  rescue RGeo::Error::RGeoError
    false
  end

  def initialize_map
    if params[:center_lat].present?
      center_lat = params[:center_lat]
    else
     center_lat = 44.5947
    end

    if params[:center_lng].present?
      center_lng = params[:center_lng]
    else
      center_lng = 33.4756
    end

    if params[:zoom].present?
      zoom = params[:zoom]
    else
      zoom = 15
    end

    map_center = [ center_lat.to_f, center_lng.to_f ]

    [ map_center.to_json, zoom.to_i ]
  end

  def get_statistics(vineyard)
    if vineyard.is_a?(ActiveRecord::Relation)
      disease_stats = vineyard
        .joins(bushes: :media_item)
        .where.not(media_items: { ai_class_id: nil })
        .group("media_items.ai_class_id")
        .count
      total = vineyard.joins(:bushes).count
    else
      disease_stats = vineyard.bushes
        .joins(:media_item)
        .where.not(media_items: { ai_class_id: nil })
        .group("media_items.ai_class_id")
        .count
      total = vineyard.bushes.count
    end

    diagnoses = disease_stats.keys.map { |id| MediaItem::DIAGNOSES.fetch(id, MediaItem::NO_DIAGNOSIS) } + [ MediaItem::NO_DIAGNOSIS ]

    {
      labels: diagnoses.pluck(:name),
      data: disease_stats.values + [ total - disease_stats.values.sum ],
      # Ключи, а не цвета: цвет по ключу берёт из палитры dashboard_charts_controller
      diagnoses: diagnoses.pluck(:key),
      total_bushes: total,
      analyzed_bushes: disease_stats.values.sum,
      healthy_count: disease_stats[2] || 0
    }
  end
end
