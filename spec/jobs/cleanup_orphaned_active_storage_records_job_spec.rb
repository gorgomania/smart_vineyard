require "rails_helper"
require "fugit"

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

    it "purges orphaned blobs in bulk together with their thumbnails" do
      jpeg = Vips::Image.black(40, 30).add(120).cast(:uchar).jpegsave_buffer
      orphans = 3.times.map do
        ActiveStorage::Blob.create_and_upload!(io: StringIO.new(jpeg), filename: "p.jpg", content_type: "image/jpeg")
      end
      thumbs = orphans.map { |b| b.variant(resize_to_limit: [ 20, 20 ]).processed.image.blob }
      ActiveStorage::Blob.where(id: orphans.map(&:id)).update_all(created_at: 2.hours.ago)

      expect { described_class.new.perform }.not_to have_enqueued_job

      expect(ActiveStorage::Blob.where(id: (orphans + thumbs).map(&:id))).to be_empty
      expect((orphans + thumbs).map { |b| ActiveStorage::Blob.service.exist?(b.key) }).to all(be false)
    end

    context "with ZIP blobs waiting for ProcessZipJob" do
      def zip_blob(age, content_type: "application/zip")
        ActiveStorage::Blob.create_before_direct_upload!(
          filename: "Photos.ZIP", byte_size: 100, checksum: "abc", content_type:
        ).tap { |b| b.update_column(:created_at, age.ago) }
      end

      it "recognizes a ZIP by extension whatever content type the browser sent" do
        blob = zip_blob(2.hours, content_type: "application/x-zip-compressed")
        described_class.new.perform
        expect(ActiveStorage::Blob.exists?(blob.id)).to be true
      end

      it "keeps a ZIP younger than the grace period" do
        blob = zip_blob(2.hours)
        described_class.new.perform
        expect(ActiveStorage::Blob.exists?(blob.id)).to be true
      end

      it "purges a ZIP older than the grace period" do
        blob = zip_blob(2.days)
        described_class.new.perform
        expect(ActiveStorage::Blob.exists?(blob.id)).to be false
      end
    end

    context "with an attachment whose record is gone" do
      let(:media_item) { create(:media_item, :with_image) }
      let(:blob)       { media_item.media.blob }

      before do
        blob.update_column(:created_at, 2.hours.ago)
        MediaItem.where(id: media_item.id).delete_all
      end

      it "removes the attachment and its unshared blob in one run" do
        described_class.new.perform
        expect(ActiveStorage::Attachment.where(blob_id: blob.id)).to be_empty
        expect(ActiveStorage::Blob.exists?(blob.id)).to be false
      end

      it "keeps a blob still shared with another record (demo copy)" do
        other = create(:media_item)
        ActiveStorage::Attachment.create!(name: "media", record: other, blob:)

        described_class.new.perform
        expect(ActiveStorage::Blob.exists?(blob.id)).to be true
        expect(other.reload.media).to be_attached
      end
    end
  end

  describe "schedule" do
    it "is registered as a valid recurring task in config/recurring.yml" do
      task = Rails.application.config_for(:recurring, env: "production")[:cleanup_orphaned_storage]

      expect(task[:class].safe_constantize).to eq(described_class)
      expect(Fugit.parse(task[:schedule])).to be_a(Fugit::Cron)
    end
  end
end
