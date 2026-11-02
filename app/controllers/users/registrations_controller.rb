# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  # Тот же колбэк с новым only заменяет девайсовский, поэтому перечисляем и его действия
  prepend_before_action :authenticate_scope!, only: [ :edit, :update, :destroy, :delete ]
  # before_action :configure_sign_up_params, only: [:create]
  # before_action :configure_account_update_params, only: [:update]

  # GET /resource/sign_up
  # def new
  #   super
  # end

  # POST /resource
  # Сообщение «подтвердите почту» Devise ставит сам (notice); здесь только убираем alert,
  # оставшийся с прошлой страницы, чтобы на входе не висели два сообщения
  def create
    super do |resource|
      flash.delete(:alert) if resource.persisted? && !resource.active_for_authentication?
    end
  end

  # GET /resource/edit
  # def edit
  #   super
  # end

  # PUT /resource
  # def update
  #   super
  # end

  # GET /users/delete — подтверждение удаления паролем
  def delete
  end

  # DELETE /resource
  # Удаляем только с верным текущим паролем, демо-аккаунт тоже
  def destroy
    password = params.dig(resource_name, :current_password)
    return super if resource.valid_password?(password)

    resource.errors.add(:current_password, password.blank? ? :blank : :invalid)
    render :delete, status: :unprocessable_entity
  end

  # GET /resource/cancel
  # Forces the session data which is usually expired after sign
  # in to be expired now. This is useful if the user wants to
  # cancel oauth signing in/up in the middle of the process,
  # removing all OAuth session data.
  # def cancel
  #   super
  # end

  # protected

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_sign_up_params
  #   devise_parameter_sanitizer.permit(:sign_up, keys: [:attribute])
  # end

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_account_update_params
  #   devise_parameter_sanitizer.permit(:account_update, keys: [:attribute])
  # end

  # The path used after sign up.
  # def after_sign_up_path_for(resource)
  #   super(resource)
  # end

  # The path used after sign up for inactive accounts.
  def after_inactive_sign_up_path_for(resource)
    new_user_session_path
  end
end
