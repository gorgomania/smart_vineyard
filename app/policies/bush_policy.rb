class BushPolicy < ApplicationPolicy
  # Свой виноградник и не удалённый: мягко удалённый (deleted_at) пользователь уже не видит
  def attach_to_bush?
    vineyard = record.row&.vineyard
    vineyard.present? && vineyard.user_id == user.id && vineyard.deleted_at.nil?
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
