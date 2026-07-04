class FolderPolicy < ApplicationPolicy
  def show?
    record.user_id == user.id
  end

  def create?
    return false unless record.user_id == user.id
    return true if record.parent_id.nil? # корневая папка, всё ок
    parent = Folder.find_by(id: record.parent_id)
    parent.present? && parent.user_id == user.id
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

  def destroy?
    show?
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
