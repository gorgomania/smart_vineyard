require "rails_helper"

RSpec.describe "Forgotten authorization", type: :request do
  let(:user)   { create(:user) }
  let(:folder) { create(:folder, user:) }

  before { sign_in user }

  it "fails an action that never called authorize" do
    allow_any_instance_of(FoldersController).to receive(:authorize)
    expect { get folder_path(folder) }.to raise_error(Pundit::AuthorizationNotPerformedError)
  end

  it "does not fail an action that opted out" do
    get vineyards_path
    expect(response).to have_http_status(:ok)
  end
end
