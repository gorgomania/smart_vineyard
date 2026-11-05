require "rails_helper"

RSpec.describe ProcessUploadsJob, type: :job do
  let(:user)   { create(:user) }
  let(:folder) { create(:folder, user:) }

  def upload_blob(filename: "photo.jpg", content_type: "image/jpeg")
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("\xFF\xD8\xFF\xE0fake content"),
      filename:,
      content_type:
    )
  end

  describe "#perform" do
    it "skips invalid signed blob IDs without raising" do
      expect {
        described_class.new.perform(folder, [ "invalid_signed_id" ])
      }.not_to raise_error
    end

    it "refreshes the open folder page now and once more a bit later" do
      blob = upload_blob
      expect {
        described_class.new.perform(folder, [ blob.signed_id ])
      }.to have_broadcasted_to(folder.to_gid_param).with(a_string_including('action="refresh"'))
        .and have_enqueued_job(RefreshFolderJob).with(folder)
    end

    it "creates a media_item for each valid blob" do
      blob = upload_blob
      expect {
        described_class.new.perform(folder, [ blob.signed_id ])
      }.to change(MediaItem, :count).by(1)
    end

    context "when folder has a vineyard and filename matches a bush" do
      it "assigns the correct bush to the media_item" do
        vineyard = create(:vineyard, user:)
        folder_with_vineyard = create(:folder, user:, vineyard:)
        row  = create(:row, vineyard:, row_number: 1)
        bush = create(:bush, vineyard:, row:, bush_number: 2)

        blob = upload_blob(filename: "Ряд 1 Куст 2.jpg")
        # Привязку делает общая DistributeMediaToBushesJob — та же, что для файлов из архива
        perform_enqueued_jobs(only: DistributeMediaToBushesJob) do
          described_class.new.perform(folder_with_vineyard, [ blob.signed_id ])
        end

        expect(MediaItem.last.bush_id).to eq(bush.id)
      end
    end
  end

  describe "edge cases" do
    # Повторная отправка формы шлёт те же блобы: два файла на одном блобе переименовывались бы вместе
    it "skips a blob that is already attached" do
      blob = upload_blob
      described_class.new.perform(folder, [ blob.signed_id ])

      expect { described_class.new.perform(folder, [ blob.signed_id ]) }.not_to change(MediaItem, :count)
      expect(ActiveStorage::Attachment.where(blob_id: blob.id).count).to eq(1)
    end

    it "does not distribute when the folder has no vineyard" do
      expect {
        described_class.new.perform(folder, [ upload_blob.signed_id ])
      }.not_to have_enqueued_job(DistributeMediaToBushesJob)
    end

    it "is discarded when the folder was deleted before it started" do
      described_class.perform_later(folder, [ upload_blob.signed_id ])
      folder.delete

      expect { perform_enqueued_jobs(only: described_class) }.not_to raise_error
      expect(MediaItem.count).to eq(0)
    end
  end

  describe "file names" do
    it "loads the folder's names once for the whole batch and dedupes inside it" do
      create(:media_item, :with_named_image, folder:, image_filename: "a.jpg")
      blobs = 3.times.map { upload_blob(filename: "a.jpg") }
      expect(MediaItem).to receive(:filenames_in_folder).once.and_call_original

      described_class.new.perform(folder, blobs.map(&:signed_id))
      expect(folder.media_items.map { |i| i.media.blob.filename.to_s }.sort).to eq([ "a(2).jpg", "a(3).jpg", "a(4).jpg", "a.jpg" ])
    end
  end
end
