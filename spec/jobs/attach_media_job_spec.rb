require "rails_helper"

RSpec.describe AttachMediaJob, type: :job do
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
        described_class.new.perform(folder_with_vineyard, [ blob.signed_id ])

        expect(MediaItem.last.bush_id).to eq(bush.id)
      end
    end
  end
end
