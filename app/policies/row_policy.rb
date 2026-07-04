class RowPolicy < ApplicationPolicy
  def bushes?
    record.vineyard.user_id == user.id
  end


  class Scope < ApplicationPolicy::Scope
    # NOTE: Be explicit about which records you allow access to!
    # def resolve
    #   scope.all
    # end
  end
end
