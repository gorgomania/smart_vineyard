require "rails_helper"

RSpec.describe DistributeMediaToBushesJob, type: :job do
  let(:user)     { create(:user) }
  let(:vineyard) { create(:vineyard, user:) }
  let(:folder)   { create(:folder, user:, vineyard:) }

  describe "#perform" do
    context "when media_item_ids is empty" do
      it "returns without raising" do
        expect { described_class.new.perform([]) }.not_to raise_error
      end
    end

    context "when folder has no vineyard" do
      it "returns without assigning bushes" do
        folder_no_vineyard = create(:folder, user:)
        item = create(:media_item, :with_named_image,
          folder: folder_no_vineyard,
          image_filename: "Ряд 1 Куст 1.jpg")
        described_class.new.perform([ item.id ])
        expect(item.reload.bush_id).to be_nil
      end
    end

    context "when filename matches a bush" do
      it "assigns the correct bush" do
        row  = create(:row, vineyard:, row_number: 2)
        bush = create(:bush, vineyard:, row:, bush_number: 3)
        item = create(:media_item, :with_named_image,
          folder:,
          image_filename: "ряд 2 куст 3.jpg")
        described_class.new.perform([ item.id ])
        expect(item.reload.bush_id).to eq(bush.id)
      end
    end

    context "when filename does not match the pattern" do
      it "does not assign a bush" do
        item = create(:media_item, :with_named_image,
          folder:,
          image_filename: "img_001.jpg")
        described_class.new.perform([ item.id ])
        expect(item.reload.bush_id).to be_nil
      end
    end
  end
end
