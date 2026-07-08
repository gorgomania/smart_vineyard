require "rails_helper"

RSpec.describe GenerateRowsAndBushesJob, type: :job do
  let(:vineyard) { create(:vineyard) }

  def perform(bushes_per_row)
    described_class.new.perform(vineyard.id, bushes_per_row)
  end

  describe "#perform" do
    context "with array input" do
      it "creates the correct number of rows" do
        perform([3, 4, 5])
        expect(vineyard.rows.count).to eq(3)
      end

      it "creates bushes with correct counts per row" do
        perform([3, 4, 5])
        counts = vineyard.rows.order(:row_number).map { |r| r.bushes.count }
        expect(counts).to eq([3, 4, 5])
      end

      it "numbers rows sequentially starting from 1" do
        perform([2, 2])
        expect(vineyard.rows.pluck(:row_number).sort).to eq([1, 2])
      end

      it "numbers bushes sequentially within each row" do
        perform([3])
        row = vineyard.rows.first
        expect(row.bushes.pluck(:bush_number).sort).to eq([1, 2, 3])
      end
    end

    context "with JSON string input" do
      it "parses the JSON and creates rows and bushes" do
        perform("[2, 3]")
        expect(vineyard.rows.count).to eq(2)
        counts = vineyard.rows.order(:row_number).map { |r| r.bushes.count }
        expect(counts).to eq([2, 3])
      end
    end

    context "when vineyard does not exist" do
      it "is discarded without raising" do
        expect {
          described_class.perform_now(-1, [3])
        }.not_to raise_error
      end
    end
  end
end
