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
      let(:jpeg) { "\xFF\xD8\xFF\xE0".b + SecureRandom.random_bytes(3.megabytes) }

      it "stores each file with correct content and checksum, then enqueues downstream jobs" do
        zip_blob = create_zip_blob("Ряд 1 Куст 1.jpg" => jpeg, "docs/readme.txt" => "skip me")

        expect {
          described_class.new.perform(folder, zip_blob)
        }.to have_enqueued_job(DistributeMediaToBushesJob).on_queue("default")
           .and have_enqueued_job(ClassifyMediaJob).on_queue("heavy").at_priority(ApplicationJob::CLASSIFICATION_PRIORITY)
           .and have_enqueued_job(GenerateImagePreviewJob).on_queue("heavy").at_priority(ApplicationJob::PREVIEW_PRIORITY)
           .and have_enqueued_job(NormalizeMediaFilenamesJob).on_queue("default").at_priority(ApplicationJob::PREVIEW_PRIORITY)

        item = folder.media_items.sole
        blob = item.media.blob
        expect(blob.filename.to_s).to eq("Ряд 1 Куст 1.jpg")
        expect(blob.content_type).to eq("image/jpeg")
        expect(blob.byte_size).to eq(jpeg.bytesize)
        expect(blob.download).to eq(jpeg)
        expect(blob.checksum).to eq(OpenSSL::Digest::MD5.base64digest(jpeg))
        expect(ActiveStorage::Blob.exists?(zip_blob.id)).to be false
      end

      it "refreshes the open folder page" do
        zip_blob = create_zip_blob("a.jpg" => "\xFF\xD8fake")

        expect {
          described_class.new.perform(folder, zip_blob)
        }.to have_broadcasted_to(folder.to_gid_param).with(a_string_including('action="refresh"'))
          .and have_enqueued_job(RefreshFolderJob).with(folder)
      end
    end

    context "when ZIP contains only unsupported file types" do
      it "creates nothing and still removes the archive" do
        zip_blob = create_zip_blob("document.pdf" => "pdf content")

        expect { described_class.new.perform(folder, zip_blob) }.not_to change(MediaItem, :count)
        expect(ActiveStorage::Blob.exists?(zip_blob.id)).to be false
      end
    end

    context "when an error occurs" do
      it "purges already extracted files but keeps the archive for a retry, and re-raises" do
        zip_blob = create_zip_blob("a.jpg" => "\xFF\xD8fake", "b.jpg" => "\xFF\xD8fake2")
        allow(MediaItem).to receive(:insert_all!).and_raise(StandardError, "db down")

        expect {
          described_class.new.perform(folder, zip_blob)
        }.to raise_error(StandardError, "db down")

        expect(ActiveStorage::Blob.pluck(:id)).to eq([ zip_blob.id ])
      end

      it "keeps saved files and removes the archive when enqueuing follow-up jobs fails" do
        zip_blob = create_zip_blob("a.jpg" => "\xFF\xD8fake")
        allow(DistributeMediaToBushesJob).to receive(:perform_later).and_raise(StandardError, "queue down")

        expect {
          described_class.new.perform(folder, zip_blob)
        }.to raise_error(StandardError, "queue down")

        expect(folder.media_items.sole.media).to be_attached
        expect(ActiveStorage::Blob.exists?(zip_blob.id)).to be false
      end
    end
  end
end
