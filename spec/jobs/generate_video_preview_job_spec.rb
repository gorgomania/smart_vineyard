require "rails_helper"

RSpec.describe GenerateVideoPreviewJob, type: :job do
  describe "#perform" do
    context "when media_item does not exist" do
      it "is discarded without raising" do
        expect { described_class.perform_now(-1) }.not_to raise_error
      end
    end
  end
end
