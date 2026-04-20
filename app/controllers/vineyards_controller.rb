class VineyardsController < ApplicationController
  def index
    @map_center, @map_zoom = initialize_map
    @draw_mode = params[:draw] == 'true'
  end

  def show
    render "index"
  end
  
  def new
    @map_center, @map_zoom = initialize_map
    @draw_mode = params[:draw] == 'true'
  end

  def create
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
