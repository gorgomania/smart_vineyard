class FolderPolicy < ApplicationPolicy
  def show?
    record.user_id == user.id
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

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(user_id: user.id)
    end
  end
end
