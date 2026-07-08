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

  describe "#display_name" do
    it "includes bush number" do
      bush.bush_number = 5
      expect(bush.display_name).to eq("Куст 5")
    end
  end
end
