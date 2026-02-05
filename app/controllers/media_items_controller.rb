class MediaItemsController < ApplicationController
  include ActionView::Helpers::NumberHelper
  def new
    @folder_id = Folder.find(params[:folder_id])
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
      if filesave_errors.presence
        errors_messages = filesave_errors
      else
        errors_messages = [ "Сначала выберите файл." ]
      end
      redirect_to new_media_item_path(folder_id: folder_id), alert: errors_messages
    end
  end

  def show
    @media_item = MediaItem.find(params[:id])
    @parent_id = @media_item.folder_id
  end

  def edit
    id = params[:id]
    @media_item = MediaItem.find(id)
  end

  def update
    @media_item = MediaItem.find(params[:id])
    @media_item.validate_media_filename(media_item_params[:filename])
    if @media_item.errors.any?
      flash.now[:alert] = @media_item.errors[:media][0]
      render "edit", status: :unprocessable_entity
    else
       @media_item.media.blob.update(filename: "#{media_item_params[:filename]}")
       redirect_to folder_path(@media_item.folder_id), notice: "Имя файла успешно изменено."
    end
  end

  def destroy
    id = params[:id]
    folder_id = MediaItem.find(id).folder_id
    MediaItem.delete(id)
    redirect_to folder_path(folder_id), notice: "Файл успешно удален."
  end

private
  def media_item_params
    params.require(:media_item).permit(:folder_id, :filename, media: [])
  end
end
