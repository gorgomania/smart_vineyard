class FoldersController < ApplicationController
  def show
    id = params[:id]
    if id.nil?
      id = 1
    end
    @folder = Folder.find(id)
    @childrens = @folder.children
  end
  def create
    title = folder_params[:title]
    parent_id = folder_params[:parent_id]
    folder = Folder.new(title: title, parent_id: parent_id)
    if folder.save
      redirect_to folder_path(parent_id), notice: "Папка успешно создана."
    else
      if folder.errors.full_messages[0] == "Title can't be blank"
         flash.now[:alert] = "Имя не может быть пустым."
      else
         flash.now[:alert] = "Имя уже используется."
      end
      @parent_id = parent_id
      render "new"
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
      redirect_to folder_path(folder.parent_id), notice: "Имя папки успешно изменено."
    else
      if folder.errors.full_messages[0] == "Title can't be blank"
         flash.now[:alert] = "Имя не может быть пустым."
      else
         flash.now[:alert] = "Имя уже используется."
      end
      @folder = folder
      render "edit"
    end
  end
  def destroy
    id = params[:id]
    parent_id = Folder.find(id).parent_id
    Folder.delete(id)
    redirect_to folder_path(parent_id), notice: "Папка успешно удалена."
  end
  private
  def folder_params
        params.require(:folders).permit(:title, :parent_id)
  end
end
