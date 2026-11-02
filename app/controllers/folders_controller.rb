class FoldersController < ApplicationController
  PER_PAGE = 24

  def index
    if params[:folders]
      title_search_query = folder_params[:title]
      if title_search_query.present?
        per_page = PER_PAGE
        if params[:page].nil?
          @page = 1
        else
          @page = params[:page].to_i
        end

        @childrens_length, @media_length = search_counts(title_search_query)
        @page_limit = page_count(@childrens_length + @media_length)
        # page=0, отрицательный или не число — первая страница, больше последней — последняя
        @page = @page.clamp(1, @page_limit)

        offset = (@page - 1) * per_page
        @childrens = policy_scope(Folder).where("title ILIKE ?", search_pattern(title_search_query)).order(created_at: :asc).limit(per_page).offset(offset)
        if @childrens.length < per_page
          if @childrens_length > offset
            offset = 0
          else
            offset -= @childrens_length
          end
          @media = policy_scope(MediaItem).joins(media_attachment: :blob).where("active_storage_blobs.filename ILIKE ?", search_pattern(title_search_query)).order(created_at: :asc).limit(per_page - @childrens.length).offset(offset).includes(media_attachment: :blob, video_preview_attachment: :blob).to_a
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
    redirect_to folder_path(root_folder.id)
  end

  def show
    per_page = PER_PAGE
    id = params[:id]
    @folder = Folder.find_by(id: id) || root_folder
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
    @page_limit = page_count(childrens_length + media_length)
    # Особые номера: -1 — страница, с которой начинаются только что загруженные файлы (MediaItemsController#create),
    # -2 — страница с последней папкой (после создания папки). Итог, как и любой другой номер, держим
    # в 1..@page_limit: иначе 0 и отрицательные дают отрицательный OFFSET и 500
    @page =
      case @page
      when -1 then ((childrens_length + media_length - params[:successfull_uploads_count].to_i) / per_page.to_f).ceil
      when -2 then (childrens_length / per_page.to_f).ceil
      else @page
      end.clamp(1, @page_limit)

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
    authorize folder

    if folder.save
      redirect_to folder_path(parent_id, page: "-2"), notice: "Папка успешно создана"
    else
      flash.now[:alert] = folder.errors[:title][0]
      @parent_id = parent_id
      render "new", status: :unprocessable_content
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

    if folder.update(title: folder_params[:title])
      if search_query.blank?
        redirect_to folder_path(folder.parent_id, page: page), notice: "Имя папки успешно изменено"
      else
        redirect_to folders_path(page: page, folders: { title: search_query }), notice: "Имя папки успешно изменено"
      end
    else
      flash.now[:alert] = folder.errors[:title][0]
      @folder = folder
      @page = page
      @search_query = search_query
      render "edit", status: :unprocessable_content
    end
  end

  def destroy
    search_query = params[:search_query]
    page = params[:page]
    folder = Folder.find(params[:id])
    authorize folder
    parent_id = folder.parent_id
    folder.delete_tree! # мгновенно в БД, файлы удалит фоновая задача
    if search_query.blank?
      if parent_id
        redirect_to folder_path(parent_id, page: page), notice: "Папка успешно удалена"
      else
        redirect_to folders_path, notice: "Папка успешно удалена"
      end
    else
      redirect_to folders_path(page: page, folders: { title: search_query }), notice: "Папка успешно удалена"
    end
  end

  def select_page
    if params[:id].present?
      @folder = Folder.find(params[:id])
      authorize @folder
    end

    @search_query = params[:search_query]

    # Диапазон приходит из ссылки, но держим его в пределах реальных страниц: иначе range_end=100000000
    # построил бы сто миллионов <option>
    page_limit =
      if @search_query.present? then page_count(search_counts(@search_query).sum)
      elsif @folder then page_count(@folder.children.count + @folder.media_items.count)
      else 1
      end
    @range_start = params[:range_start].to_i.clamp(1, page_limit)
    @range_end = params[:range_end].to_i.clamp(1, page_limit)

    if request.post?
      page = params[:page].to_i
      if @search_query.present?
        redirect_to folders_path(folders: { title: @search_query }, page: page)
      elsif @folder
        redirect_to folder_path(@folder, page: page)
      else
        redirect_to folders_path
      end
    end
  end

  def attach
    @folder = Folder.find(params[:id])
    authorize @folder

    @vineyards = current_user.vineyards.active.free.order(:name)
  end

  def attach_to_vineyard
    @folder = Folder.find(params[:id])
    @vineyard = Vineyard.active.find(params[:vineyard_id])

    authorize @folder
    authorize @vineyard

    if @folder.update(vineyard: @vineyard)
      DistributeMediaToBushesJob.perform_later(@folder.id)
      redirect_to @folder, notice: "Папка успешно прикреплена к винограднику"
    else
      flash[:alert] = "Выбранный виноградник уже занят другой папкой"
      redirect_to attach_folder_path(@folder)
    end
  end

  def edit_attach
    @folder = Folder.find(params[:id])
    authorize @folder

    @vineyards = current_user.vineyards.active.free(keep_vineyard_id: @folder.vineyard_id).order(:name)

    if @folder.vineyard.present?
      @selected_vineyard_id = @folder.vineyard.id
    end
  end

  def update_attach_to_vineyard
    @folder = Folder.find(params[:id])
    @vineyard = Vineyard.active.find(params[:vineyard_id])

    authorize @folder
    authorize @vineyard

    if @folder.update(vineyard: @vineyard)
      DistributeMediaToBushesJob.perform_later(@folder.id)
      redirect_to @folder, notice: "Папка успешно перекреплена к винограднику"
    else
      flash[:alert] = "Выбранный виноградник уже занят другой папкой"
      redirect_to edit_attach_folder_path(@folder)
    end
  end

  def detach_from_vineyard
    @folder = Folder.find(params[:id])
    authorize @folder

    @folder.update(vineyard: nil)
    DistributeMediaToBushesJob.perform_later(@folder.id)
    redirect_to @folder, notice: "Папка успешно откреплена от виноградника"
  end

  private

  # Сколько папок и файлов пользователя подходят под поиск по названию
  def search_counts(query)
    pattern = search_pattern(query)
    [
      policy_scope(Folder).where("title ILIKE ?", pattern).count,
      policy_scope(MediaItem).joins(media_attachment: :blob).where("active_storage_blobs.filename ILIKE ?", pattern).count
    ]
  end

  # Шаблон ILIKE «содержит query»: % и _ из запроса — обычные символы, а не «что угодно» и «любой символ»
  def search_pattern(query)
    "%#{Folder.sanitize_sql_like(query)}%"
  end

  # Число страниц по PER_PAGE; пустая папка или поиск без результатов — одна страница
  def page_count(items_count)
    [ (items_count / PER_PAGE.to_f).ceil, 1 ].max
  end

  def folder_params
    params.require(:folders).permit(:title, :parent_id)
  end

  # Корень — папка пользователя без родителя. Ищем не по названию: после переименования корня
  # создался бы новый пустой «Root», а всё дерево осталось бы недоступным
  def root_folder
    roots = current_user.folders.where(parent_id: nil).order(:id)
    roots.first || current_user.folders.create!(title: "Root")
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    roots.first! # параллельный запрос успел создать корень раньше
  end
end
