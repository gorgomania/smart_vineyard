class UsersController < ApplicationController
  skip_after_action :verify_authorized # пустая страница, данных нет

  def index
  end
end
