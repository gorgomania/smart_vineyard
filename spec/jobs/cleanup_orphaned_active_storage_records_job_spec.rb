require "rails_helper"

RSpec.describe CleanupOrphanedActiveStorageRecordsJob, type: :job do
  describe "#perform" do
    it "runs without raising when there are no orphans" do
      expect { described_class.new.perform }.not_to raise_error
    end

    it "purges orphaned blobs older than 1 hour" do
      blob = ActiveStorage::Blob.create_before_direct_upload!(
        filename: "orphan.jpg",
        byte_size: 100,
        checksum: "abc",
        content_type: "image/jpeg"
      )
      blob.update_column(:created_at, 2.hours.ago)

      expect {
        described_class.new.perform
      }.to change(ActiveStorage::Blob, :count).by(-1)
    end
  end
end
