class VineyardsController < ApplicationController
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
    @map_center, @map_zoom = initialize_map
    @mode = "new"

    @vineyard = current_user.vineyards.new(session.delete(:vineyard_params) || {})
    if @vineyard.polygon.present?
    @vineyard_data = {
      polygon: @vineyard.polygon.to_s,
      row_spacing: @vineyard.row_spacing.to_f,
      bush_spacing: @vineyard.bush_spacing.to_f,
      reference_side_index: @vineyard.reference_side_index,
      reference_vertex_is_first: @vineyard.reference_vertex_is_first
    }
    else
      @vineyard_data = nil
    end

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

    @errors = session.delete(:vineyard_errors)
  end

  def create
    # Удаляем временные поля вершин из params перед созданием
    vineyard_params = vineyard_params_permit
    @vineyard = current_user.vineyards.build(vineyard_params)
    if @vineyard.save
      bushes_per_row = params[:vineyard][:bushes_per_row]
      GenerateRowsAndBushesJob.perform_later(@vineyard.id, bushes_per_row)
      redirect_to @vineyard, notice: "Виноградник создан"
    else
      session[:vineyard_params] = vineyard_params.to_h
      session[:vineyard_errors] = @vineyard.errors.full_messages
      redirect_to new_vineyard_path
    end
  end

  def edit
    @map_center, @map_zoom = initialize_map
    @mode = "edit"

    @vineyard = Vineyard.active.find(params[:id])
    # Если есть параметры в сессии (после ошибки валидации), используем их
    if session[:vineyard_params].present?
      @vineyard.assign_attributes(session[:vineyard_params])
      session.delete(:vineyard_params)
    end
    @errors = session.delete(:vineyard_errors)
    authorize @vineyard
    @vineyard_data = {
      polygon: @vineyard.polygon.to_s,
      row_spacing: @vineyard.row_spacing.to_f,
      bush_spacing: @vineyard.bush_spacing.to_f,
      reference_side_index: @vineyard.reference_side_index,
      reference_vertex_is_first: @vineyard.reference_vertex_is_first
    }

    @vineyards = policy_scope(Vineyard).active.for_index.where.not(id: params[:id])
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

  def update
    @vineyard = Vineyard.active.find(params[:id])
    authorize @vineyard
    vineyard_params = vineyard_params_permit

    if @vineyard.update(vineyard_params)
      RegenerateRowsAndBushesJob.perform_later(@vineyard.id, params[:vineyard][:bushes_per_row])
      redirect_to @vineyard, notice: "Виноградник обновлён"
    else
      session[:vineyard_params] = vineyard_params.to_h
      session[:vineyard_errors] = @vineyard.errors.full_messages
      redirect_to edit_vineyard_path(id: params[:id])
    end
  end

  def destroy
    vineyard = Vineyard.active.find(params[:id])
    authorize vineyard
    vineyard.destroy
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

  def rows
    vineyard = Vineyard.active.find(params[:id])
    authorize vineyard
    rows = vineyard.rows
                  .left_joins(:bushes)
                  .group(:id, :row_number)
                  .order(:row_number)
                  .pluck(:id, :row_number, "COUNT(bushes.id)")

    render json: rows.map { |id, row_number, count| { id:, row_number:, bushes_count: count } }
  end

  private

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
      3 => "#D63384"  # Антракноз
    } [class_id] || "#AAAAAA"
  end
end
