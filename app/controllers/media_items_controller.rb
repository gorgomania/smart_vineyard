class MediaItemsController < ApplicationController
  include ActionView::Helpers::NumberHelper
  def show
    @media_item = MediaItem.find(params[:id])
    authorize @media_item
    @parent_id = @media_item.folder_id
    @folder = Folder.find_by(id: @parent_id)
    @title_path = @folder.title_path + [ @media_item.media.filename ]
    @id_path = @folder.id_path
  end

  def new
    @folder_id = params[:folder_id]
    @media_item = MediaItem.new
  end

  def create
    folder_id =  media_item_params[:folder_id]
    media_items = media_item_params[:media]
    successfull_uploads_counter = 0
    filesave_errors = []
    media_items.each do |file|
      if file.present?
        media_item = MediaItem.new(folder_id: folder_id)
        media_item.media.attach(file)
        if media_item.save
          successfull_uploads_counter += 1
        else
          filesave_errors.push(media_item.errors[:media][0])
        end
      end
    end
    if successfull_uploads_counter.nonzero?
      redirect_to folder_path(folder_id, page: "-1", successfull_uploads_count: successfull_uploads_counter), notice: "Файлы в количестве #{successfull_uploads_counter} успешно загружены"
    else
      flash[:alert] = [ "Сначала выберите файл" ]
      redirect_to new_media_item_path(folder_id: folder_id)
    end
  end

  def edit
    @page = params[:page]
    @search_query = params[:search_query]
    @media_item = MediaItem.find(params[:id])
    authorize @media_item
  end

  def update
    @media_item = MediaItem.find(params[:id])
    authorize @media_item
    @media_item.media.blob.filename = "#{media_item_params[:filename]}"
    search_query = params[:media_item][:search_query]
    page = params[:media_item][:page]
    if @media_item.valid?
      @media_item.media.blob.save
      if search_query.empty?
        redirect_to folder_path(@media_item.folder_id, page: page), notice: "Имя файла успешно изменено"
      else
        redirect_to folders_path(page: page, folders: { title: search_query }), notice: "Имя файла успешно изменено"
      end
    else
      @search_query = search_query
      @page = page
      flash.now[:alert] = @media_item.errors[:media][0]
      render "edit", status: :unprocessable_entity
    end
  end

  def destroy
    search_query = params[:search_query]
    page = params[:page]
    media_item = MediaItem.find(params[:id])
    authorize media_item
    folder_id = media_item.folder_id
    media_item.destroy
    if search_query.empty?
      redirect_to folder_path(folder_id, page: page), notice: "Файл успешно удален"
    else
      redirect_to folders_path(page: page, folders: { title: search_query }), notice: "Файл успешно удален"
    end
  end

  def classify
    id = params[:id]
    media_item = MediaItem.find(id)
    authorize media_item
    media_item.classify!
    redirect_to media_item_path(id)
  end

  def attach
    @media_item = MediaItem.find(params[:id])
    @vineyards = current_user.vineyards.order(:name)
  end

  def attach_to_bush
    @media_item = MediaItem.find(params[:id])
    @bush = Bush.find(params[:bush_id])
    if @media_item.update(bush: @bush)
      redirect_to @media_item, notice: "Медиа успешно прикреплено к кусту"
    else
      flash[:alert] = "Выбранный куст уже занят"
      redirect_to attach_media_item_path(@media_item)
    end
  end

  def edit_attach
    @media_item = MediaItem.find(params[:id])
    @vineyards = current_user.vineyards.order(:name)
    @selected_vineyard_id = @media_item.bush.vineyard_id
    @selected_row_id = @media_item.bush.row_id
    @selected_bush_id = @media_item.bush_id
    # Загружаем ряды для выбранного виноградника
    if @selected_vineyard_id.present?
      @rows = Vineyard.find(@selected_vineyard_id).rows.order(:row_number)
    else
      @rows = []
    end

    # Загружаем кусты (как объекты для options_from_collection_for_select)
    if @selected_row_id.present?
      @bushes = Row.find(@selected_row_id).bushes.order(:bush_number)
    else
      @bushes = []
    end
  end

  def update_attach_to_bush
    @media_item = MediaItem.find(params[:id])
    @bush = Bush.find(params[:bush_id])
    if @media_item.update(bush: @bush)
      redirect_to @media_item, notice: "Медиа успешно переприкреплено к кусту"
    else
      flash[:alert] = "Выбранный куст уже занят"
      redirect_to edit_attach_media_item_path(@media_item)
    end
  end

  def detach_from_bush
    @media_item = MediaItem.find(params[:id])
    @media_item.update(bush: nil)
    redirect_to @media_item, notice: "Медиа успешно откреплено от куста"
  end

private
  def media_item_params
    params.require(:media_item).permit(:folder_id, :filename, media: [])
  end
end
