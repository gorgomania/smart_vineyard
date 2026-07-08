require "rails_helper"

RSpec.describe DestroyVineyardJob, type: :job do
  let(:vineyard) { create(:vineyard) }

  describe "#perform" do
    it "deletes the vineyard record" do
      vineyard
      expect {
        described_class.new.perform(vineyard.id)
      }.to change(Vineyard, :count).by(-1)
    end

    it "destroys all rows" do
      create(:row, vineyard:, row_number: 1)
      create(:row, vineyard:, row_number: 2)
      described_class.new.perform(vineyard.id)
      expect(Row.where(vineyard_id: vineyard.id)).to be_empty
    end

    it "detaches folder from vineyard without deleting it" do
      folder = create(:folder, vineyard:)
      described_class.new.perform(vineyard.id)
      expect(folder.reload.vineyard_id).to be_nil
    end

    context "when vineyard does not exist" do
      it "is discarded without raising" do
        expect {
          described_class.perform_now(-1)
        }.not_to raise_error
      end
    end
  end
end
