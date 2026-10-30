require "rails_helper"

RSpec.describe Vineyard, type: :model do
  subject(:vineyard) { build(:vineyard) }

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:rows).dependent(:delete_all) }
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

  describe "#soft_destroy" do
    it "sets deleted_at and leaves the actual deletion to the job" do
      vineyard = create(:vineyard)
      expect { vineyard.soft_destroy }.not_to change(Vineyard, :count)
      expect(vineyard.reload.deleted_at).not_to be_nil
      expect(DestroyVineyardJob).to have_been_enqueued.with(vineyard.id)
    end
  end

  describe "#destroy" do
    it "deletes the record with its rows and bushes, keeping the media and the folder" do
      vineyard = create(:vineyard)
      row = create(:row, vineyard:, row_number: 1)
      bush = create(:bush, vineyard:, row:, bush_number: 1)
      folder = create(:folder, user: vineyard.user, vineyard:)
      media_item = create(:media_item, folder:, bush:)

      expect { vineyard.destroy }.to change(Vineyard, :count).by(-1)
      expect(Row.exists?(row.id)).to be false
      expect(Bush.exists?(bush.id)).to be false
      expect(media_item.reload.bush_id).to be_nil
      expect(folder.reload.vineyard_id).to be_nil
    end
  end

  describe "#bushes_diagnoses" do
    it "maps 'row-bush' to [media item id, class] for bushes with a file only" do
      vineyard = create(:vineyard)
      row = create(:row, vineyard:, row_number: 2)
      create(:bush, vineyard:, row:, bush_number: 1)
      bush = create(:bush, vineyard:, row:, bush_number: 4)
      item = create(:media_item, bush:, ai_class_id: 1)

      expect(vineyard.bushes_diagnoses).to eq("2-4" => [ item.id, 1 ])
    end
  end

  describe "#area_hectares=" do
    it "strips ' га' suffix from string values" do
      vineyard.area_hectares = "2.5 га"
      expect(vineyard.area_hectares).to eq(2.5)
    end
  end
end
