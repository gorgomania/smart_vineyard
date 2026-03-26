class MediaItemsController < ApplicationController
  include ActionView::Helpers::NumberHelper
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
      redirect_to folder_path(folder_id), notice: "Файлы в количестве #{successfull_uploads_counter} успешно загружены."
    else
      flash.now[:alert] = [ "Сначала выберите файл." ]
      @folder_id = folder_id
      @media_item = MediaItem.new
      render "new", status: :unprocessable_entity
    end
  end

  def show
    @media_item = MediaItem.find(params[:id])
    @parent_id = @media_item.folder_id
    @folder = Folder.find_by(id: @parent_id)
    @title_path = @folder.title_path + [ @media_item.media.filename ]
    @id_path = @folder.id_path
  end

  def edit
    id = params[:id]
    @media_item = MediaItem.find(id)
  end

  def update
    @media_item = MediaItem.find(params[:id])
    @media_item.media.blob.filename = "#{media_item_params[:filename]}"
    if @media_item.valid?
      @media_item.media.blob.save
      redirect_to folder_path(@media_item.folder_id), notice: "Имя файла успешно изменено."
    else
      flash.now[:alert] = @media_item.errors[:media][0]
      render "edit", status: :unprocessable_entity
    end
  end

  def destroy
    id = params[:id]
    folder_id = MediaItem.find(id).folder_id
    MediaItem.delete(id)
    redirect_to folder_path(folder_id), notice: "Файл успешно удален."
  end

  def classify
    id = params[:id]
    media_item = MediaItem.find(id)
    media_item.classify!
    redirect_to media_item_path(id)
  end

private
  def media_item_params
    params.require(:media_item).permit(:folder_id, :filename, media: [])
  end
end
