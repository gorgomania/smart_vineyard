class FoldersController < ApplicationController
  def index
    if params[:folders]
      title_search_query = folder_params[:title]
      if title_search_query.present?
        per_page = 24
        if params[:page].nil?
          @page = 1
        else
          @page = params[:page].to_i
        end

        @childrens_length = policy_scope(Folder).where("title ILIKE ?", "%#{title_search_query}%").count
        @media_length = policy_scope(MediaItem).joins(media_attachment: :blob).where("active_storage_blobs.filename ILIKE ?", "%#{title_search_query}%").includes(media_attachment: :blob, video_preview_attachment: :blob).to_a.count
        @page_limit = ((@childrens_length + @media_length) / per_page.to_f).ceil
        @page_limit = 1 if @page_limit.zero?
        if @page > @page_limit
          @page = @page_limit
        end

        offset = (@page - 1) * per_page
        @childrens = policy_scope(Folder).where("title ILIKE ?", "%#{title_search_query}%").order(created_at: :asc).limit(per_page).offset(offset)
        if @childrens.length < per_page
          if @childrens_length > offset
            offset = 0
          else
            offset -= @childrens_length
          end
          @media = policy_scope(MediaItem).joins(media_attachment: :blob).where("active_storage_blobs.filename ILIKE ?", "%#{title_search_query}%").order(created_at: :asc).limit(per_page - @childrens.length).offset(offset).includes(media_attachment: :blob, video_preview_attachment: :blob).to_a
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
    redirect_to folder_path(Folder.find_or_create_by(title: "Root", parent_id: nil, user_id: current_user.id).id)
  end

  def show
    per_page = 24
    id = params[:id]
    @folder = Folder.find_by(id: id)
    if @folder.nil?
      @folder = Folder.find_or_create_by(title: "Root", parent_id: nil, user_id: current_user.id)
    end
    authorize @folder
    if params[:page].blank?
      @page = 1
    else
      @page = params[:page].to_i
    end
    @title_path = @folder.title_path
    @id_path = @folder.id_path
    @parent_id = @folder.parent_id

    childrens_length = @folder.children.count
    media_length = @folder.media_items.count
    @page_limit = ((childrens_length + media_length) / per_page.to_f).ceil
    @page_limit = 1 if @page_limit.zero?
    if @page > @page_limit
      @page = @page_limit
    elsif @page == -1
      @page = ((childrens_length + media_length - params[:successfull_uploads_count].to_i) / per_page.to_f).ceil
      @page = 1 if @page.zero?
    elsif @page == -2
      @page = (childrens_length / per_page.to_f).ceil
    end

    offset = (@page - 1) * per_page
    @childrens = @folder.children.order(created_at: :asc).limit(per_page).offset(offset)
    if @childrens.length < per_page
      if childrens_length > offset
        offset = 0
      else
        offset -= childrens_length
      end
        @media = @folder.media_items.order(created_at: :asc).limit(per_page - @childrens.length).offset(offset).includes(media_attachment: :blob, video_preview_attachment: :blob).to_a
    else
      @media = []
    end
    @search_query = ""
  end

  def new
    @parent_id = params[:parent_id]
  end

  def create
    title = folder_params[:title]
    parent_id = folder_params[:parent_id]
    folder = Folder.new(title: title, parent_id: parent_id, user_id: current_user.id)
    if folder.save
      redirect_to folder_path(parent_id, page: "-2"), notice: "Папка успешно создана"
    else
      flash.now[:alert] = folder.errors[:title][0]
      @parent_id = parent_id
      render "new", status: :unprocessable_entity
    end
  end

  def edit
    @page = params[:page]
    @search_query = params[:search_query]
    @folder = Folder.find(params[:id])
    authorize @folder
  end

  def update
    folder = Folder.find(params[:id])
    authorize folder
    search_query = params[:folders][:search_query]
    page = params[:folders][:page]
    folder.update(title: folder_params[:title])
    if folder.save
      if search_query.empty?
        redirect_to folder_path(folder.parent_id, page: page), notice: "Имя папки успешно изменено"
      else
        redirect_to folders_path(page: page, folders: { title: search_query }), notice: "Имя папки успешно изменено"
      end
    else
      flash.now[:alert] = folder.errors[:title][0]
      @folder = folder
      @page = page
      @search_query = search_query
      render "edit", status: :unprocessable_entity
    end
  end

  def destroy
    search_query = params[:search_query]
    page = params[:page]
    folder = Folder.find(params[:id])
    authorize folder
    parent_id = folder.parent_id
    folder.destroy
    if search_query.empty?
      if parent_id
        redirect_to folder_path(parent_id, page: page), notice: "Папка успешно удалена"
      else
        redirect_to folders_path, notice: "Папка успешно удалена"
      end
    else
      redirect_to folders_path(page: page, folders: { title: search_query }), notice: "Папка успешно удалена"
    end
  end

  def attach
    @folder = Folder.find(params[:id])
    @vineyards = current_user.vineyards.order(:name)
  end

  def attach_to_vineyard
    @folder = Folder.find(params[:id])
    @vineyard = Vineyard.find(params[:vineyard_id])
    if @folder.update(vineyard: @vineyard)
      redirect_to @folder, notice: "Папка успешно связана с виноградником"
    else
      flash[:alert] = "Выбранный виноградник уже занят другой папкой"
      redirect_to attach_folder_path(@folder)
    end
  end

  def detach_from_vineyard
    @folder = Folder.find(params[:id])
    @folder.update(vineyard: nil)
    redirect_to @folder, notice: "Папка успешно откреплена от виноградника"
  end

  private

  def folder_params
    params.require(:folders).permit(:title, :parent_id)
  end
end
