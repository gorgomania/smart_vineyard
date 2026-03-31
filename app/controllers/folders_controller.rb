class FoldersController < ApplicationController
  def index
    if params[:folders]
      title_search_query = folder_params[:title]
      if title_search_query.present?
        @childrens = Folder.where("title ILIKE ?", "%#{title_search_query}%")
        @media = MediaItem.joins(media_attachment: :blob).where("active_storage_blobs.filename ILIKE ?", "%#{title_search_query}%").includes(media_attachment: :blob, video_preview_attachment: :blob).to_a
        @search_query = title_search_query
        if params[:page].nil?
          @page = 1
        else
          @page = params[:page].to_i
        end
        if @childrens.empty? && @media.empty?
          flash.now[:alert] = "В результате поиска не обнаружено папок и файлов с похожим именем"
        end
        render "show"
        return
      end
    end
    redirect_to folder_path(Folder.find_or_create_by(title: "Root", parent_id: nil).id)
  end
  def show
    id = params[:id]
    @folder = Folder.find_by(id: id)
    if @folder.nil?
      @folder = Folder.find_or_create_by(title: "Root", parent_id: nil)
    end
    @title_path = @folder.title_path
    @id_path = @folder.id_path
    @parent_id = @folder.parent_id
    @childrens = @folder.children
    @media = @folder.media_items.includes(media_attachment: :blob).to_a
    @search_query = ""
    if params[:page].nil?
      @page = 1
    else
      @page = params[:page].to_i
    end
  end
  def create
    title = folder_params[:title]
    parent_id = folder_params[:parent_id]
    folder = Folder.new(title: title, parent_id: parent_id)
    if folder.save
      redirect_to folder_path(parent_id), notice: "Папка успешно создана"
    else
      flash.now[:alert] = folder.errors[:title][0]
      @parent_id = parent_id
      render "new", status: :unprocessable_entity
    end
  end
  def new
    @parent_id = params[:parent_id]
  end
  def edit
    id = params[:id]
    @folder = Folder.find(id)
  end
  def update
    folder = Folder.find(params[:id])
    folder.update(title: folder_params[:title])
    if folder.save
      redirect_to folder_path(folder.parent_id), notice: "Имя папки успешно изменено"
    else
      flash.now[:alert] = folder.errors[:title][0]
      @folder = folder
      render "edit", status: :unprocessable_entity
    end
  end
  def destroy
    id = params[:id]
    parent_id = Folder.find(id).parent_id
    Folder.delete(id)
    if parent_id
      redirect_to folder_path(parent_id), notice: "Папка успешно удалена"
    else
      redirect_to folder_path, notice: "Папка успешно удалена"
    end
  end
  private
  def folder_params
    params.require(:folders).permit(:title, :parent_id)
  end
end
