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
      flash[:alert] = ["Сначала выберите файл"]
      redirect_to new_media_item_path(folder_id: folder_id, page: page)
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

private
  def media_item_params
    params.require(:media_item).permit(:folder_id, :filename, media: [])
  end
end
