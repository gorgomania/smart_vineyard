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

    context "reading the archive" do
      it "opens it in place on the Disk service, without a copy in tmp" do
        zip_blob = create_zip_blob("a.jpg" => "\xFF\xD8fake")
        expect(zip_blob).not_to receive(:open)

        expect { described_class.new.perform(folder, zip_blob) }.to change(MediaItem, :count).by(1)
      end

      it "downloads it to a temp file on services without local paths (S3 and the like)" do
        zip_blob = create_zip_blob("a.jpg" => "\xFF\xD8fake")
        allow(zip_blob.service).to receive(:respond_to?).and_call_original
        allow(zip_blob.service).to receive(:respond_to?).with(:path_for).and_return(false)
        expect(zip_blob).to receive(:open).and_call_original

        expect { described_class.new.perform(folder, zip_blob) }.to change(MediaItem, :count).by(1)
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

  describe "file names" do
    # «Сжатая ZIP-папка» Windows пишет русские имена в CP866 без флага UTF-8
    it "reads Russian names written by Windows Explorer in CP866" do
      zip_blob = create_zip_blob("Ряд 1 Куст 1.jpg".encode("CP866").b => "\xFF\xD8fake")
      described_class.new.perform(folder, zip_blob)

      expect(folder.media_items.sole.media.blob.filename.to_s).to eq("Ряд 1 Куст 1.jpg")
    end

    it "keeps UTF-8 names written without the UTF-8 flag (macOS, 7-Zip)" do
      zip_blob = create_zip_blob("Ряд 2 Куст 3.jpg".b => "\xFF\xD8fake")
      described_class.new.perform(folder, zip_blob)

      expect(folder.media_items.sole.media.blob.filename.to_s).to eq("Ряд 2 Куст 3.jpg")
    end

    it "generates a preview for a video and does not classify it" do
      described_class.new.perform(folder, create_zip_blob("clip.mp4" => "fake"))

      expect(GenerateVideoPreviewJob).to have_been_enqueued.with(folder.media_items.sole.id)
      expect(ClassifyMediaJob).not_to have_been_enqueued
      expect(GenerateImagePreviewJob).not_to have_been_enqueued
    end
  end

  describe "limits" do
    # ZIP-бомба: архив отклоняется целиком, распакованное и сам архив убираются, повторять нечего
    def expect_rejected(zip_blob)
      expect { described_class.new.perform(folder, zip_blob) }.not_to raise_error
      expect(MediaItem.count).to eq(0)
      expect(ActiveStorage::Blob.count).to eq(0)
    end

    it "rejects an archive with too many files" do
      stub_const("#{described_class}::MAX_ENTRIES", 2)
      expect_rejected(create_zip_blob("a.jpg" => "1", "b.jpg" => "2", "c.jpg" => "3"))
    end

    it "rejects an archive that unpacks too large" do
      stub_const("#{described_class}::MAX_TOTAL_SIZE", 5.kilobytes)
      expect_rejected(create_zip_blob("a.jpg" => "a" * 4.kilobytes, "b.jpg" => "b" * 4.kilobytes))
    end

    it "stops extracting when an entry turns out bigger than its header said" do
      zip_blob = create_zip_blob("a.jpg" => "a" * 4.kilobytes)
      allow_any_instance_of(Zip::Entry).to receive(:size).and_return(1) # подделанный заголовок
      stub_const("#{described_class}::CHUNK_SIZE", 1.kilobyte)
      stub_const("#{described_class}::MAX_ENTRY_SIZE", 2.kilobytes)
      expect_rejected(zip_blob)
    end

    # Заголовки подделаны, поэтому предел срабатывает только на второй записи, когда первая уже сохранена
    context "when a later entry breaks a limit" do
      before do
        allow_any_instance_of(Zip::Entry).to receive(:size).and_return(1)
        stub_const("#{described_class}::CHUNK_SIZE", 1.kilobyte)
      end

      it "removes the files already extracted when the entry is too big" do
        stub_const("#{described_class}::MAX_ENTRY_SIZE", 2.kilobytes)
        expect_rejected(create_zip_blob("a.jpg" => "a" * 1.kilobyte, "b.jpg" => "b" * 4.kilobytes))
      end

      it "removes the files already extracted when the total is too big" do
        stub_const("#{described_class}::MAX_TOTAL_SIZE", 3.kilobytes)
        expect_rejected(create_zip_blob("a.jpg" => "a" * 2.kilobytes, "b.jpg" => "b" * 2.kilobytes))
      end
    end

    it "is discarded when the folder was deleted before it started" do
      zip_blob = create_zip_blob("a.jpg" => "\xFF\xD8fake")
      described_class.perform_later(folder, zip_blob)
      folder.delete

      expect { perform_enqueued_jobs(only: described_class) }.not_to raise_error
    end
  end
end
