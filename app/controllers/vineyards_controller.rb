class VineyardsController < ApplicationController
  LAYOUT_ATTRIBUTES = %w[polygon row_spacing bush_spacing reference_side_index reference_vertex_is_first].freeze
  LAYOUT_NOT_CALCULATED_MESSAGE = "Не удалось рассчитать ряды и кусты. Дождитесь загрузки карты и попробуйте снова".freeze

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
    if params[:bushes_vision].present? && params[:bushes_vision] == "true"
      @bushes_vision = @vineyard.bushes_diagnoses
    else
      @bushes_vision = false
    end
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
    bushes_per_row = parse_bushes_per_row(params[:vineyard][:bushes_per_row])

    if bushes_per_row.nil?
      @vineyard.valid? # чтобы вместе показать и остальные ошибки формы
      @vineyard.errors.add(:base, LAYOUT_NOT_CALCULATED_MESSAGE)
      setup_new_form_data
      render :new, status: :unprocessable_entity
    elsif @vineyard.save
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
    # Ряды пересчитываем только при изменении геометрии и только по валидной раскладке с карты:
    # пустой "[]" (карта не пересчитала поле) иначе удалил бы все ряды и кусты
    layout_changed = @vineyard.changed.intersect?(LAYOUT_ATTRIBUTES)
    bushes_per_row = parse_bushes_per_row(params[:vineyard][:bushes_per_row])

    if layout_changed && bushes_per_row.nil?
      @vineyard.valid?
      @vineyard.errors.add(:base, LAYOUT_NOT_CALCULATED_MESSAGE)
      setup_edit_form_data
      render :edit, status: :unprocessable_entity
    elsif @vineyard.save
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
      else
        redirect_to stats_vineyard_path(params[:vineyard_id])
      end
    end
  end

  def bushes_per_row
    vineyard = Vineyard.active.find(params[:id])
    authorize vineyard
    data = vineyard.rows.order(:row_number).pluck(Arel.sql("( SELECT COUNT(*) FROM bushes WHERE bushes.row_id = rows.id )"))
    render json: data
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

  # Массив непустой, из целых >= 0, хотя бы один ряд с кустами; иначе nil
  def parse_bushes_per_row(raw)
    counts = JSON.parse(raw.to_s)
    return unless counts.is_a?(Array) && counts.all? { |c| c.is_a?(Integer) && c >= 0 } && counts.any?(&:positive?)

    counts
  rescue JSON::ParserError
    nil
  end

  def vineyard_params_permit
    vertices = []
    params[:vineyard].each do |key, value|
      if key =~ /vertex_(\d+)_lat/
        index = $1.to_i
        vertices[index] ||= {}
        vertices[index][:lat] = value.to_f
      elsif key =~ /vertex_(\d+)_lng/
        index = $1.to_i
        vertices[index] ||= {}
        vertices[index][:lng] = value.to_f
      end
    end

    # Убираем nil и сортируем по индексу
    vertices = vertices.compact

    if vertices.size >= 3
      # Создаем WKT в правильном формате (lng lat)
      wkt_points = vertices.map { |v| "#{v[:lng]} #{v[:lat]}" }.join(", ")
      wkt = "POLYGON((#{wkt_points}, #{vertices[0][:lng]} #{vertices[0][:lat]}))"

      params[:vineyard][:polygon] = wkt
    end

    params[:vineyard].delete_if { |k, v| k.to_s.match?(/\Avertex_\d+_(lat|lng)\z/) }

    params.require(:vineyard).permit(
      :name, :grape_variety, :planting_year, :row_spacing, :bush_spacing,
      :polygon, :reference_side_index, :reference_vertex_is_first,
      :area_hectares, :total_rows, :total_bushes
    )
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

    disease_names = {
      0 => "Чёрная гниль",
      1 => "Эска",
      2 => "Здоровый",
      3 => "Листовой ожог"
    }

    {
      labels: disease_stats.keys.map { |id| disease_names[id] } + [ "Нет данных" ],
      data: disease_stats.values + [ total - disease_stats.values.sum ],
      colors: disease_stats.keys.map { |id| disease_color(id) } + [ "#AAAAAA" ],
      total_bushes: total,
      analyzed_bushes: disease_stats.values.sum,
      healthy_count: disease_stats[2] || 0
    }
  end

  def disease_color(class_id)
    {
      0 => "#800000",  # Чёрная гниль
      1 => "#FF8C00",  # Эска
      2 => "#2ECC40",  # Здоровый
      3 => "#D63384"   # Листовой ожог
    } [class_id] || "#AAAAAA"
  end
end
