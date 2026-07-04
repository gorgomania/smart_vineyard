class BushPolicy < ApplicationPolicy
  def attach_to_bush?
    record.row.vineyard.user_id == user.id
  end

  def update_attach_to_bush?
    attach_to_bush?
  end

  class Scope < ApplicationPolicy::Scope
    # NOTE: Be explicit about which records you allow access to!
    # def resolve
    #   scope.all
    # end
  end
end
