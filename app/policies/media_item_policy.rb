class MediaItemPolicy < ApplicationPolicy
  def show?
    record.folder.user_id == user.id
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

  def classify?
    show?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.joins(:folder).where(folders: { user_id: user.id })
    end
  end
end
