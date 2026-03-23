class FoldersController < ApplicationController
  def index
    if params[:folders]
      title_search_query = folder_params[:title]
      if title_search_query.present?
        @childrens = Folder.where("title ILIKE ?", "%#{title_search_query}%")
        @media = MediaItem.joins(media_attachment: :blob).where("active_storage_blobs.filename ILIKE ?", "%#{title_search_query}%")
        @search_query = title_search_query
        render "show"
        return
      end
    end
    @folder = Folder.find_or_create_by(title: "Root", parent_id: nil)
    @title_path = @folder.title_path
    @id_path = @folder.id_path
    @parent_id = @folder.parent_id
    @childrens = @folder.children
    @media = @folder.media_items
    @search_query = ""
    render "show"
  end
  def show
    id = params[:id]
    @folder = Folder.find_by(id: id)
    if @folder.nil?
      redirect_to folders_path
      return
    end
    @title_path = @folder.title_path
    @id_path = @folder.id_path
    @parent_id = @folder.parent_id
    @childrens = @folder.children
    @media = @folder.media_items
    @search_query = ""
  end
  def create
    title = folder_params[:title]
    parent_id = folder_params[:parent_id]
    folder = Folder.new(title: title, parent_id: parent_id)
    if folder.save
      redirect_to folder_path(parent_id), notice: "Папка успешно создана."
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
      redirect_to folder_path(folder.parent_id), notice: "Имя папки успешно изменено."
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
      redirect_to folder_path(parent_id), notice: "Папка успешно удалена."
    else
      redirect_to folder_path, notice: "Папка успешно удалена."
    end
  end
  private
  def folder_params
    params.require(:folders).permit(:title, :parent_id)
  end
end
