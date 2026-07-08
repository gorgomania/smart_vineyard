require "rails_helper"

RSpec.describe GenerateImagePreviewJob, type: :job do
  describe "#perform" do
    context "when media_item does not exist" do
      it "is discarded without raising" do
        expect { described_class.perform_now(-1) }.not_to raise_error
      end
    end

    context "when media_item exists" do
      it "processes the image variant" do
        item = create(:media_item, :with_image)
        variant_double = double("variant", processed: true)
        allow_any_instance_of(MediaItem).to receive_message_chain(:media, :variant).and_return(variant_double)

        described_class.new.perform(item.id)

        expect(variant_double).to have_received(:processed)
      end
    end
  end
end
