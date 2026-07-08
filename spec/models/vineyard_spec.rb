require "rails_helper"

RSpec.describe Vineyard, type: :model do
  subject(:vineyard) { build(:vineyard) }

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:rows).dependent(:destroy) }
    it { is_expected.to have_many(:bushes).through(:rows) }
    it { is_expected.to have_one(:folder).dependent(:nullify) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:user_id) }
    it { is_expected.to validate_length_of(:grape_variety).is_at_most(50) }
    it "rejects area_hectares of 0" do
      vineyard.area_hectares = 0
      expect(vineyard).not_to be_valid
    end

    it "rejects area_hectares above 10" do
      vineyard.area_hectares = 10.1
      expect(vineyard).not_to be_valid
    end
    it { is_expected.to validate_numericality_of(:row_spacing).is_greater_than_or_equal_to(2.0).is_less_than_or_equal_to(3.0) }
    it { is_expected.to validate_numericality_of(:bush_spacing).is_greater_than_or_equal_to(1.2).is_less_than_or_equal_to(1.8) }
    it { is_expected.to validate_numericality_of(:total_rows).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:total_bushes).is_greater_than(0) }
  end

  describe "scopes" do
    describe ".active" do
      it "excludes soft-deleted vineyards" do
        user = create(:user)
        active = create(:vineyard, user:)
        deleted = create(:vineyard, user:, name: "Deleted", deleted_at: Time.current)

        expect(Vineyard.active).to include(active)
        expect(Vineyard.active).not_to include(deleted)
      end
    end
  end

  describe "#destroy" do
    it "sets deleted_at instead of deleting the record" do
      vineyard = create(:vineyard)
      expect { vineyard.destroy }.not_to change(Vineyard, :count)
      expect(vineyard.reload.deleted_at).not_to be_nil
    end
  end

  describe "#area_hectares=" do
    it "strips ' га' suffix from string values" do
      vineyard.area_hectares = "2.5 га"
      expect(vineyard.area_hectares).to eq(2.5)
    end
  end
end
