class MediaItemsController < ApplicationController
  include ActionView::Helpers::NumberHelper

  def show
    @media_item = MediaItem.find(params[:id])
    authorize @media_item
    @class_names = GrapeClassifier.class_names
    @parent_id = @media_item.folder_id
    @folder = @media_item.folder
    @title_path = @folder.title_path + [ @media_item.media.filename ]
    @id_path = @folder.id_path
  end

  def new
    @folder_id = params[:folder_id]
    @media_item = MediaItem.new
  end

  def create
    @folder = Folder.find(media_item_params[:folder_id])
    authorize @folder, :create_media_item?

    # Все файлы, включая ZIP, браузер уже загрузил через DirectUpload и прислал только signed id
    blob_ids = params[:signed_blob_ids].to_s.split(",").compact_blank
                     .select { |id| own_upload?(ActiveStorage::Blob.find_signed(id)) }
    zip_blobs = params[:signed_zip_ids].to_s.split(",").compact_blank
                      .filter_map { |id| ActiveStorage::Blob.find_signed(id) }
                      .select { |blob| own_upload?(blob) && blob.filename.extension.casecmp?("zip") }

    # Проверяем, было ли что-то загружено
    if zip_blobs.blank? && blob_ids.blank?
      flash[:alert] = [ "Сначала выберите файл" ]
      redirect_to new_media_item_path(folder_id: @folder)
      return
    end

    zip_blobs.each { |zip_blob| ProcessZipJob.perform_later(@folder, zip_blob) }

    # Обрабатываем обычные файлы если есть
    if blob_ids.present?
      AttachMediaJob.perform_later(@folder, blob_ids)
    end

    # Формируем сообщение
    messages = []
    messages << "#{zip_blobs.count} ZIP #{Russian.p(zip_blobs.count, 'архив', 'архива', 'архивов')}" if zip_blobs.present?
    messages << "#{blob_ids.count} #{Russian.p(blob_ids.count, 'файл', 'файла', 'файлов')}" if blob_ids.present?

    redirect_to folder_path(@folder, page: "-1"), notice: "#{messages.join(' и ')} загружаются в фоне"
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

    new_base_name = media_item_params[:filename]

    if new_base_name.blank?
      flash.now[:alert] = "Имя файла не может быть пустым"
      render "edit", status: :unprocessable_entity
      return
    end

    # Имя хранится в блобе: общий блоб (демо-копии) сначала копируем, чтобы не переименовать чужой файл
    blob = @media_item.ensure_own_media_blob!

    new_filename = "#{new_base_name}#{blob.filename.extension_with_delimiter}"
    blob.filename = new_filename
    @media_item.normalize_filename!

    if blob.save
      if search_query.blank?
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
    old_vineyard_id = media_item.bush&.vineyard_id
    media_item.destroy
    Vineyard.broadcast_diagnoses_changed(old_vineyard_id)
    if search_query.blank?
      redirect_to folder_path(folder_id, page: page), notice: "Файл успешно удален"
    else
      redirect_to folders_path(page: page, folders: { title: search_query }), notice: "Файл успешно удален"
    end
  end

  def classify
    media_item = MediaItem.find(params[:id])
    authorize media_item
    # Пользователь ждёт результат: в обход очереди массовой классификации
    ClassifyMediaJob.set(priority: 0).perform_later(media_item.id)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "analysis-panel-#{media_item.id}",
          partial: "media_items/analysis_panel",
          locals: { media_item: media_item, class_names: GrapeClassifier.class_names, processing: true }
        )
      end
      format.html { redirect_to media_item_path(media_item), notice: "Классификация запущена" }
    end
  end

  def attach
    @media_item = MediaItem.find(params[:id])
    authorize @media_item

    @vineyards = current_user.vineyards.active.order(:name)
  end

  def attach_to_bush
    @media_item = MediaItem.find(params[:id])
    @bush = Bush.find(params[:bush_id])

    authorize @media_item
    authorize @bush

    old_vineyard_id = @media_item.bush&.vineyard_id
    if @media_item.update(bush: @bush)
      Vineyard.broadcast_diagnoses_changed([ old_vineyard_id, @bush.vineyard_id ])
      redirect_to @media_item, notice: "Файл успешно прикреплен к кусту"
    else
      flash[:alert] = "Выбранный куст уже занят другим файлом"
      redirect_to attach_media_item_path(@media_item)
    end
  end

  def edit_attach
    @media_item = MediaItem.find(params[:id])
    authorize @media_item

    @vineyards = current_user.vineyards.active.order(:name)

    if @media_item.bush.present?
      @selected_vineyard_id = @media_item.bush.vineyard_id
      @selected_row_id = @media_item.bush.row_id
      @selected_bush_id = @media_item.bush_id
    end

    # Загружаем ряды для выбранного виноградника
    if @selected_vineyard_id.present?
      @rows = Row.with_free_bushes(Vineyard.active.find(@selected_vineyard_id), keep_bush_id: @media_item.bush_id)
    else
      @rows = []
    end

    # Загружаем кусты (как объекты для options_from_collection_for_select)
    if @selected_row_id.present?
      @bushes = Row.find(@selected_row_id).bushes.free(keep_bush_id: @media_item.bush_id).order(:bush_number)
    else
      @bushes = []
    end
  end

  def update_attach_to_bush
    @media_item = MediaItem.find(params[:id])
    @bush = Bush.find(params[:bush_id])

    authorize @media_item
    authorize @bush

    old_vineyard_id = @media_item.bush&.vineyard_id
    if @media_item.update(bush: @bush)
      Vineyard.broadcast_diagnoses_changed([ old_vineyard_id, @bush.vineyard_id ])
      redirect_to @media_item, notice: "Файл успешно перекреплен к кусту"
    else
      flash[:alert] = "Выбранный куст уже занят другим файлом"
      redirect_to edit_attach_media_item_path(@media_item)
    end
  end

  def detach_from_bush
    @media_item = MediaItem.find(params[:id])
    authorize @media_item

    old_vineyard_id = @media_item.bush&.vineyard_id
    @media_item.update(bush: nil)
    Vineyard.broadcast_diagnoses_changed(old_vineyard_id)
    redirect_to @media_item, notice: "Файл успешно откреплен от куста"
  end

private
  def media_item_params
    params.require(:media_item).permit(:folder_id, :filename)
  end

  # signed id сам по себе не доказывает владение: проверяем, что файл загрузил этот пользователь
  def own_upload?(blob)
    blob.present? && blob.metadata["user_id"] == current_user.id
  end
end
