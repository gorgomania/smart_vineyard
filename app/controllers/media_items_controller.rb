class MediaItemsController < ApplicationController
  include ActionView::Helpers::NumberHelper

  def show
    @media_item = MediaItem.find(params[:id])
    authorize @media_item
    @class_names = GrapeClassifier.class_names
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
    folder_id = media_item_params[:folder_id]
    blob_ids = params[:signed_blob_ids]&.split(",")
    uploaded_files = params[:media_item][:media].select(&:present?)

    # Находим все ZIP среди загруженных файлов
    zip_files = uploaded_files.select { |f| f.original_filename.to_s.end_with?(".zip") }

    # Проверяем, было ли что-то загружено
    if zip_files.blank? && blob_ids.blank?
      flash[:alert] = [ "Сначала выберите файл" ]
      redirect_to new_media_item_path(folder_id: folder_id)
      return
    end

    # Обрабатываем все ZIP
    zip_files.each do |zip_file|
      zip_filename = "#{SecureRandom.hex(8)}_#{zip_file.original_filename}"
      temp_path = Rails.root.join("tmp", "zip_upload", zip_filename)
      FileUtils.mkdir_p(File.dirname(temp_path))
      File.binwrite(temp_path, zip_file.read)
      ProcessZipJob.perform_later(folder_id, temp_path.to_s)
    end

    # Обрабатываем обычные файлы если есть
    if blob_ids.present?
      AttachMediaJob.perform_later(folder_id, blob_ids)
    end

    # Формируем сообщение
    messages = []
    messages << "#{zip_files.count} ZIP #{Russian.p(zip_files.count, 'архив', 'архива', 'архивов')}" if zip_files.present?
    messages << "#{blob_ids.count} #{Russian.p(blob_ids.count, 'файл', 'файла', 'файлов')}" if blob_ids.present?

    redirect_to folder_path(folder_id, page: "-1"), notice: "#{messages.join(' и ')} загружаются в фоне"
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

    search_query = params[:search_query]
    page = params[:page]

    blob = @media_item.media.blob
    new_base_name = media_item_params[:filename]

    if new_base_name.blank?
      flash.now[:alert] = "Имя файла не может быть пустым"
      render "edit", status: :unprocessable_entity
      return
    end

    new_filename = "#{new_base_name}#{blob.filename.extension_with_delimiter}"
    blob.filename = new_filename
    @media_item.normalize_filename!

    if blob.save
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
      redirect_to @media_item, notice: "Файл успешно прикреплен к кусту"
    else
      flash[:alert] = "Выбранный куст уже занят другим файлом"
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
      redirect_to @media_item, notice: "Файл успешно перекреплен к кусту"
    else
      flash[:alert] = "Выбранный куст уже занят другим файлом"
      redirect_to edit_attach_media_item_path(@media_item)
    end
  end

  def detach_from_bush
    @media_item = MediaItem.find(params[:id])
    @media_item.update(bush: nil)
    redirect_to @media_item, notice: "Файл успешно откреплен от куста"
  end

private
  def media_item_params
    params.require(:media_item).permit(:folder_id, :filename, media: [])
  end
end
