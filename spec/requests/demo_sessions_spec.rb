require "rails_helper"

RSpec.describe "DemoSessions", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:demo_user) { create(:user, demo_temp: true, demo_expires_at: 24.hours.from_now) }

  before do
    DemoSessionsController::RATE_LIMIT_STORE.clear
    allow(DemoCloneService).to receive(:call).and_return(demo_user)
  end

  describe "POST /demo_session" do
    it "signs in the demo user and schedules cleanup" do
      expect {
        post demo_session_path
      }.to have_enqueued_job(CleanupDemoUserJob).with(demo_user.id)
      expect(response).to redirect_to(root_path)
    end

    it "redirects to login when the demo master is not configured" do
      allow(DemoCloneService).to receive(:call).and_raise(ActiveRecord::RecordNotFound)

      post demo_session_path
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to eq("Демо недоступно")
    end

    it "stops cloning after 10 requests per hour from one IP" do
      10.times { post demo_session_path }
      post demo_session_path

      expect(DemoCloneService).to have_received(:call).exactly(10).times
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to eq("Слишком много демо-входов. Попробуйте позже")
    end

    it "allows requests again after the window passes" do
      10.times { post demo_session_path }

      travel 61.minutes do
        post demo_session_path
        expect(response).to redirect_to(root_path)
      end
    end

    it "stops cloning after 100 requests per hour across all IPs" do
      100.times { |i| post demo_session_path, env: { "REMOTE_ADDR" => "10.1.#{i / 250}.#{i % 250}" } }
      post demo_session_path, env: { "REMOTE_ADDR" => "10.9.9.9" }

      expect(DemoCloneService).to have_received(:call).exactly(100).times
      expect(flash[:alert]).to eq("Демо временно недоступно. Попробуйте позже")
    end
  end
end
