require "rails_helper"

RSpec.describe DistributeFolderToBushesJob, type: :job do
  let(:user)     { create(:user) }
  let(:vineyard) { create(:vineyard, user:) }
  let(:folder)   { create(:folder, user:, vineyard:) }

  describe "#perform" do
    context "when folder does not exist" do
      it "returns without raising" do
        expect { described_class.new.perform(-1) }.not_to raise_error
      end
    end

    context "when folder has no vineyard" do
      it "does not assign any bushes" do
        folder_no_vineyard = create(:folder, user:)
        item = create(:media_item, :with_named_image,
          folder: folder_no_vineyard,
          image_filename: "Ряд 1 Куст 1.jpg")
        described_class.new.perform(folder_no_vineyard.id)
        expect(item.reload.bush_id).to be_nil
      end
    end

    context "when filename matches a bush" do
      it "assigns the correct bush to the media_item" do
        row = create(:row, vineyard:, row_number: 1)
        bush = create(:bush, vineyard:, row:, bush_number: 1)
        item = create(:media_item, :with_named_image,
          folder:,
          image_filename: "Ряд 1 Куст 1.jpg")
        described_class.new.perform(folder.id)
        expect(item.reload.bush_id).to eq(bush.id)
      end
    end

    context "when filename does not match the pattern" do
      it "does not assign a bush" do
        create(:row, vineyard:, row_number: 1)
        item = create(:media_item, :with_named_image,
          folder:,
          image_filename: "random_photo.jpg")
        described_class.new.perform(folder.id)
        expect(item.reload.bush_id).to be_nil
      end
    end
  end
end
