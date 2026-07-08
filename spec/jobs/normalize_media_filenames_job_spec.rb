require "rails_helper"

RSpec.describe NormalizeMediaFilenamesJob, type: :job do
  let(:folder) { create(:folder, user: create(:user)) }

  describe "#perform" do
    it "does not raise for valid media items" do
      items = create_list(:media_item, 2, :with_image, folder:)
      expect { described_class.new.perform(items.map(&:id)) }.not_to raise_error
    end

    it "calls normalize_filename! on each media_item" do
      items = create_list(:media_item, 2, :with_image, folder:)
      call_count = 0
      allow_any_instance_of(MediaItem).to receive(:normalize_filename!) { call_count += 1; false }
      described_class.new.perform(items.map(&:id))
      expect(call_count).to eq(2)
    end
  end
end
