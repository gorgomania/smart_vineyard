class VineyardsController < ApplicationController
  def index
    @map_center, @map_zoom = initialize_map
    @mode = 'index'
    @vineyards = policy_scope(Vineyard).for_index
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
    @mode = 'show'
    if params[:bushes_vision].present?
      @bushes_vision = params[:bushes_vision] == "true"
    else
      @bushes_vision = false
    end
    @vineyard = Vineyard.find_by(id: params[:id])
    authorize @vineyard
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
    @mode = 'new'
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
    @errors = session.delete(:vineyard_errors)
  end

  def create

    # Удаляем временные поля вершин из params перед созданием
    vineyard_params = vineyard_params_permit
  
    @vineyard = current_user.vineyards.build(vineyard_params)
    if @vineyard.save
      redirect_to @vineyard, notice: "Виноградник создан"
    else
      session[:vineyard_params] = vineyard_params.to_h
      session[:vineyard_errors] = @vineyard.errors.full_messages
      redirect_to new_vineyard_path
    end
  end

  def edit
    @map_center, @map_zoom = initialize_map
    @mode = 'edit'
    @vineyard = Vineyard.find_by(id: params[:id])
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
  end

  def update
    @vineyard = Vineyard.find_by(id: params[:id])
    authorize @vineyard
    vineyard_params = vineyard_params_permit

    @vineyard.update(vineyard_params)
    if @vineyard.save
      redirect_to @vineyard, notice: "Виноградник обновлён"
    else
      session[:vineyard_params] = vineyard_params.to_h
      session[:vineyard_errors] = @vineyard.errors.full_messages
      redirect_to edit_vineyard_path(id: params[:id])
    end
  end

  def destroy
    vineyard = Vineyard.find_by(id: params[:id])
    authorize vineyard
    vineyard.destroy
    redirect_to vineyards_path, notice: "Виноградник успешно удалён"
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
      wkt_points = vertices.map { |v| "#{v[:lng]} #{v[:lat]}" }.join(', ')
      wkt = "POLYGON((#{wkt_points}, #{vertices[0][:lng]} #{vertices[0][:lat]}))"
      
      params[:vineyard][:polygon] = wkt
    end

    params[:vineyard].delete_if { |k, v| k.to_s.match?(/\Avertex_\d+_(lat|lng)\z/) }

    if params[:vineyard][:bushes_per_row].is_a?(String)
      params[:vineyard][:bushes_per_row] = JSON.parse(params[:vineyard][:bushes_per_row])
    end

    params.require(:vineyard).permit(
      :name, :grape_variety, :planting_year, :row_spacing, :bush_spacing,
      :polygon, :reference_side_index, :reference_vertex_is_first,
      :area_hectares, :total_rows, :total_bushes, { bushes_per_row: [] }
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

    map_center = [center_lat.to_f, center_lng.to_f]

    map_center = [center_lat.to_f, center_lng.to_f]
  
    [map_center.to_json, zoom.to_i]
  end
end
