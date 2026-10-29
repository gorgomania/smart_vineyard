require "rails_helper"
require "zip"

RSpec.describe ProcessZipJob, type: :job do
  let(:user)   { create(:user) }
  let(:folder) { create(:folder, user:) }

  def create_zip_blob(entries)
    buffer = Zip::OutputStream.write_buffer do |zip|
      entries.each { |name, content| zip.put_next_entry(name); zip.write(content) }
    end
    buffer.rewind
    ActiveStorage::Blob.create_and_upload!(io: buffer, filename: "test.zip", content_type: "application/zip")
  end

  describe "#perform" do
    context "with valid images in ZIP" do
      it "creates media_items and enqueues downstream jobs" do
        zip_blob = create_zip_blob("photo.jpg" => "\xFF\xD8\xFF\xE0fake")

        allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_return(
          instance_double(ActiveStorage::Blob, id: 1, content_type: "image/jpeg")
        )
        allow(MediaItem).to receive(:insert_all!).and_return(
          [ { "id" => 1 } ]
        )
        allow(ActiveStorage::Attachment).to receive(:insert_all!)

        expect {
          described_class.new.perform(folder, zip_blob)
        }.to have_enqueued_job(DistributeMediaToBushesJob)
           .and have_enqueued_job(NormalizeMediaFilenamesJob)

        expect(ActiveStorage::Blob.exists?(zip_blob.id)).to be false
      end
    end

    context "when ZIP contains unsupported file types" do
      it "skips unsupported files" do
        zip_blob = create_zip_blob("document.pdf" => "pdf content")

        expect(ActiveStorage::Blob).not_to receive(:create_and_upload!)

        allow(MediaItem).to receive(:insert_all!).and_return([])
        allow(ActiveStorage::Attachment).to receive(:insert_all!)

        described_class.new.perform(folder, zip_blob)
      end
    end

    context "when an error occurs" do
      it "purges the zip blob and re-raises" do
        zip_blob = create_zip_blob("photo.jpg" => "\xFF\xD8fake")
        allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_raise(StandardError, "upload failed")

        expect {
          described_class.new.perform(folder, zip_blob)
        }.to raise_error(StandardError, "upload failed")

        expect(ActiveStorage::Blob.exists?(zip_blob.id)).to be false
      end
    end
  end
end
