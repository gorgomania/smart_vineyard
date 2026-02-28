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
    media_items.each do |uploaded_file|
      if uploaded_file.present?
        media_item = MediaItem.new(folder_id: folder_id)
        new_filename = get_valid_media_filename(uploaded_file.original_filename, folder_id)
        media_item.media.attach(
          io: uploaded_file.tempfile,
          filename: new_filename,
          content_type: uploaded_file.content_type
        )
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
      redirect_to new_media_item_path(folder_id: folder_id), alert: [ "Сначала выберите файл." ]
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
    new_filename = get_valid_media_filename(media_item_params[:filename], @media_item.folder_id, params[:id])
    if new_filename.length == 0
      flash.now[:alert] = "Имя не может быть пустым."
      render "edit", status: :unprocessable_entity
    else
       @media_item.media.blob.update(filename: "#{new_filename}")
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

  def get_valid_media_filename(filename, folder_id, id = nil)
    # Если проверяется имя при создании
    if id.nil?
      files_in_same_folder = MediaItem.where(folder_id: folder_id).joins(media_attachment: :blob).where(active_storage_attachments: { name: "media" })
    # Если проверяется имя при обновлении
    else
      files_in_same_folder = MediaItem.where(folder_id: folder_id).where.not(id: id).joins(media_attachment: :blob).where(active_storage_attachments: { name: "media" })
    end
    index = 0
    filename_is_not_valid = true
    while filename_is_not_valid
      filename_is_not_valid = false
      files_in_same_folder.each do |file|
        if index == 0
          if file.media.filename == filename
            index += 1
            filename_is_not_valid = true
            break
          end
        else
          if file.media.filename == filename + " (" + index.to_s() + ")"
            index += 1
            filename_is_not_valid = true
            break
          end
        end
      end
    end
    if index == 0
      filename
    else
      filename + " (" + index.to_s() + ")"
    end
  end
end
