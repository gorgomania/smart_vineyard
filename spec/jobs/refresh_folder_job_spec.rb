require "rails_helper"

RSpec.describe RefreshFolderJob, type: :job do
  it "broadcasts a page refresh to the folder stream" do
    folder = create(:folder)
    expect {
      described_class.perform_now(folder)
    }.to have_broadcasted_to(folder.to_gid_param).with(a_string_including('action="refresh"'))
  end
end
