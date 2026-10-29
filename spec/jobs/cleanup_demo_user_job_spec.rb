require "rails_helper"

RSpec.describe CleanupDemoUserJob, type: :job do
  describe "#perform" do
    it "destroys the demo user with all their data" do
      demo = create(:user, demo_temp: true, demo_expires_at: 1.hour.ago)
      folder = create(:folder, user: demo)
      create(:vineyard, user: demo)

      described_class.new.perform(demo.id)

      expect(User.exists?(demo.id)).to be false
      expect(Folder.exists?(folder.id)).to be false
      expect(Vineyard.where(user_id: demo.id)).to be_empty
    end

    it "never touches a regular user even if given their id" do
      user = create(:user)
      described_class.new.perform(user.id)
      expect(User.exists?(user.id)).to be true
    end

    it "does nothing when the user is already gone" do
      expect { described_class.new.perform(-1) }.not_to raise_error
    end

    it "keeps the master's files that the demo copy shared" do
      master_item = create(:media_item, :with_image)
      blob = master_item.media.blob
      demo = create(:user, demo_temp: true, demo_expires_at: 1.hour.ago)
      demo_item = create(:media_item, folder: create(:folder, user: demo))
      ActiveStorage::Attachment.create!(name: "media", record: demo_item, blob:)

      perform_enqueued_jobs { described_class.new.perform(demo.id) }

      expect(ActiveStorage::Blob.exists?(blob.id)).to be true
      expect(master_item.reload.media).to be_attached
    end
  end
end
