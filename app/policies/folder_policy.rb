class FolderPolicy < ApplicationPolicy
  def show?
    record.user_id == user.id
  end

  # Только внутри своей папки. Корень создаёт FoldersController#root_folder в обход политики
  def create?
    record.user_id == user.id && record.parent&.user_id == user.id
  end

  def create_media_item?
    show?
  end

  def edit?
    show?
  end

  def update?
    show?
  end

  # Корень удалять нельзя: вместе с ним ушло бы всё дерево пользователя
  def destroy?
    show? && record.parent_id.present?
  end

  def select_page?
    show?
  end

  def attach?
    show?
  end

  def attach_to_vineyard?
    show?
  end

  def edit_attach?
    show?
  end

  def update_attach_to_vineyard?
    show?
  end

  def detach_from_vineyard?
    show?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(user_id: user.id)
    end
  end
end
