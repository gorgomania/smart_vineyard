class FoldersController < ApplicationController

  def index
    @per_page = 21
    if params[:folders]
      title_search_query = folder_params[:title]
      if title_search_query.present?
        if params[:page].nil?
          @page = 1
        else
          @page = params[:page].to_i
        end
        offset = (@page - 1) * @per_page
        @childrens = Folder.where("title ILIKE ?", "%#{title_search_query}%").limit(@per_page).offset(offset)
        @childrens_length = Folder.where("title ILIKE ?", "%#{title_search_query}%").count
        @media_length = MediaItem.joins(media_attachment: :blob).where("active_storage_blobs.filename ILIKE ?", "%#{title_search_query}%").includes(media_attachment: :blob, video_preview_attachment: :blob).to_a.count
        if @childrens.length < @per_page
          if @childrens_length > offset
            offset = 0
          else
            offset -= @childrens_length
          end
            @media = MediaItem.joins(media_attachment: :blob).where("active_storage_blobs.filename ILIKE ?", "%#{title_search_query}%").limit(@per_page - @childrens.length).offset(offset).includes(media_attachment: :blob, video_preview_attachment: :blob).to_a
        else
          @media = []
        end
        @search_query = title_search_query
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
    @per_page = 21
    id = params[:id]
    @folder = Folder.find_by(id: id)
    if @folder.nil?
      @folder = Folder.find_or_create_by(title: "Root", parent_id: nil)
    end
    if params[:page].nil?
      @page = 1
    else
      @page = params[:page].to_i
    end
    @title_path = @folder.title_path
    @id_path = @folder.id_path
    @parent_id = @folder.parent_id
    offset = (@page - 1) * @per_page
    @childrens = @folder.children.limit(@per_page).offset(offset)
    @childrens_length = @folder.children.count
    @media_length = @folder.media_items.count
    if @childrens.length < @per_page
      if @childrens_length > offset
        offset = 0
      else
        offset -= @childrens_length
      end
        @media = @folder.media_items.limit(@per_page - @childrens.length).offset(offset).includes(media_attachment: :blob, video_preview_attachment: :blob).to_a
    else
      @media = []
    end
    @search_query = ""
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
