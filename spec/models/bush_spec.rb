require "rails_helper"

RSpec.describe Bush, type: :model do
  subject(:bush) { build(:bush) }

  describe "associations" do
    it { is_expected.to belong_to(:row) }
    it { is_expected.to belong_to(:vineyard) }
    it { is_expected.to have_one(:media_item).dependent(:nullify) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:bush_number) }
    it { is_expected.to validate_uniqueness_of(:bush_number).scoped_to(:row_id) }
  end

  describe ".insert_numbered!" do
    let(:vineyard) { create(:vineyard) }
    let(:row1) { Row.create!(vineyard:, row_number: 101) }
    let(:row2) { Row.create!(vineyard:, row_number: 102) }

    it "inserts every number of each row's range, with the vineyard and timestamps" do
      described_class.insert_numbered!(vineyard.id, { row1.id => 1..3, row2.id => 5..6 })

      bushes = described_class.where(row_id: [ row1.id, row2.id ])
      expect(bushes.order(:row_id, :bush_number).pluck(:row_id, :bush_number))
        .to eq([ [ row1.id, 1 ], [ row1.id, 2 ], [ row1.id, 3 ], [ row2.id, 5 ], [ row2.id, 6 ] ])
      expect(bushes.pluck(:vineyard_id).uniq).to eq([ vineyard.id ])
      expect(bushes.where(created_at: nil).or(bushes.where(updated_at: nil))).to be_empty
    end

    it "skips empty ranges and does nothing without rows" do
      expect { described_class.insert_numbered!(vineyard.id, {}) }.not_to change(described_class, :count)
      expect { described_class.insert_numbered!(vineyard.id, { row1.id => 1..0, row2.id => 1..2 }) }
        .to change(described_class, :count).by(2)
    end
  end

  describe "#display_name" do
    it "includes bush number" do
      bush.bush_number = 5
      expect(bush.display_name).to eq("Куст 5")
    end
  end
end
