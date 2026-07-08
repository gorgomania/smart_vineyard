require "rails_helper"

RSpec.describe Row, type: :model do
  subject(:row) { build(:row) }

  describe "associations" do
    it { is_expected.to belong_to(:vineyard) }
    it { is_expected.to have_many(:bushes).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:row_number) }
    it { is_expected.to validate_uniqueness_of(:row_number).scoped_to(:vineyard_id) }
  end

  describe "#display_name" do
    it "includes row number and bush count" do
      row = create(:row, row_number: 3)
      expect(row.display_name).to include("Ряд 3")
    end

    it "uses correct Russian plural for bushes" do
      row = create(:row, row_number: 1)
      create(:bush, row:, vineyard: row.vineyard, bush_number: 1)
      expect(row.display_name).to include("куст")
    end
  end
end
