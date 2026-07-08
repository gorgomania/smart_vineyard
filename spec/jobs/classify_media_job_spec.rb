require "rails_helper"

RSpec.describe ClassifyMediaJob, type: :job do
  describe "#perform" do
    context "when media_item does not exist" do
      it "returns without raising" do
        expect { described_class.new.perform(-1) }.not_to raise_error
      end
    end

    context "when media is not attached" do
      it "returns false from classify!" do
        item = create(:media_item)
        expect(described_class.new.perform(item.id)).to be_falsy
      end
    end

    context "when media is attached" do
      it "calls classify! on the media_item" do
        item = create(:media_item, :with_image)
        expect_any_instance_of(MediaItem).to receive(:classify!).and_return(true)
        described_class.new.perform(item.id)
      end
    end
  end
end
