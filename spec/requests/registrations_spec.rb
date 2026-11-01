require "rails_helper"

RSpec.describe "Users::Registrations", type: :request do
  describe "POST /users (sign up)" do
    let(:valid_params) do
      {
        user: {
          email: "new@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    it "creates a user" do
      expect {
        post user_registration_path, params: valid_params
      }.to change(User, :count).by(1)
    end

    it "redirects to login after sign up (account not yet confirmed)" do
      post user_registration_path, params: valid_params
      expect(response).to redirect_to(new_user_session_path)
    end

    it "does not set flash alert after sign up" do
      post user_registration_path, params: valid_params
      follow_redirect!
      expect(flash[:alert]).to be_nil
    end

    it "does not create user with invalid email" do
      expect {
        post user_registration_path, params: { user: { email: "bad", password: "password123", password_confirmation: "password123" } }
      }.not_to change(User, :count)
    end
  end

  describe "account deletion" do
    let(:user) { create(:user) }

    it "requires sign in for the confirmation page" do
      get delete_user_registration_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "shows the confirmation page with a password field" do
      sign_in user
      get delete_user_registration_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("user[current_password]")
    end

    it "deletes the account with the correct password" do
      sign_in user
      expect {
        delete user_registration_path, params: { user: { current_password: "password123" } }
      }.to change(User, :count).by(-1)
    end

    it "redirects straight to sign in so the goodbye notice survives" do
      sign_in user
      delete user_registration_path, params: { user: { current_password: "password123" } }
      expect(response).to redirect_to(new_user_session_path)
      follow_redirect!
      expect(response.body).to include(I18n.t("devise.registrations.destroyed"))
    end

    it "keeps the account with a wrong password" do
      sign_in user
      expect {
        delete user_registration_path, params: { user: { current_password: "wrong" } }
      }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Текущий пароль имеет неверное значение")
    end

    it "keeps the account without a password" do
      sign_in user
      expect {
        delete user_registration_path
      }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Текущий пароль не может быть пустым")
    end

    context "demo account" do
      let(:user) { create(:user, demo_temp: true, demo_expires_at: 1.hour.from_now) }

      it "shows the password field too" do
        sign_in user
        get delete_user_registration_path
        expect(response.body).to include("user[current_password]")
      end

      it "keeps the account without a password" do
        sign_in user
        expect {
          delete user_registration_path
        }.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
