class RowPolicy < ApplicationPolicy
  # Как BushPolicy: свой и не удалённый виноградник
  def bushes?
    vineyard = record.vineyard
    vineyard.present? && vineyard.user_id == user.id && vineyard.deleted_at.nil?
  end


  class Scope < ApplicationPolicy::Scope
    # NOTE: Be explicit about which records you allow access to!
    # def resolve
    #   scope.all
    # end
  end
end
