class VineyardsController < ApplicationController
  def index
    @map_center, @map_zoom = initialize_map
    @draw_mode = params[:draw] == 'true'
  end

  def show
    @map_center, @map_zoom = initialize_map
    @draw_mode = params[:draw] == 'true'
    render "index"
  end
  
  def new
    @map_center, @map_zoom = initialize_map
    @draw_mode = params[:draw] == 'true'
  end

  def create
    vertices = []
    params[:vineyards].each do |key, value|
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
      
      params[:vineyards][:polygon] = wkt
    end

    params[:vineyards].delete_if { |k, v| k.to_s.match?(/\Avertex_\d+_(lat|lng)\z/) }
    
    # Удаляем временные поля вершин из params перед созданием
    vineyard_params = params.require(:vineyards).permit(
      :name, :grape_variety, :planting_year, :row_spacing, :bush_spacing,
      :polygon, :reference_side_index, :reference_vertex_is_first,
      :area_hectares, :total_rows, :total_bushes, :bushes_per_row
    )
  
    @vineyard = current_user.vineyards.build(vineyard_params)
    
    if @vineyard.save
      redirect_to @vineyard, notice: "Виноградник создан"
    else
      render :new
    end
  end

  private

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
