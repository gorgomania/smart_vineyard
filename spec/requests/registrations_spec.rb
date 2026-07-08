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
end
