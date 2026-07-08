require "rails_helper"

RSpec.describe MediaItem, type: :model do
  let(:user)     { create(:user) }
  let(:vineyard) { create(:vineyard, user:) }
  let(:folder)   { create(:folder, user:, vineyard:) }

  subject(:media_item) { build(:media_item, folder:) }

  describe "associations" do
    it { is_expected.to belong_to(:folder) }
    it { is_expected.to belong_to(:bush).optional }
  end

  describe "validations" do
    it "prevents two media_items from linking to the same bush" do
      row  = create(:row, vineyard:, row_number: 1)
      bush = create(:bush, vineyard:, row:, bush_number: 1)
      create(:media_item, folder:, bush:)
      duplicate = build(:media_item, folder:, bush:)
      expect(duplicate).not_to be_valid
    end
  end

  describe "#row_number" do
    it "returns nil when no bush is assigned" do
      expect(media_item.row_number).to be_nil
    end

    it "returns the row number through bush" do
      row  = create(:row, vineyard:, row_number: 4)
      bush = create(:bush, vineyard:, row:, bush_number: 1)
      media_item.bush = bush
      expect(media_item.row_number).to eq(4)
    end
  end

  describe "#vineyard_name" do
    it "returns nil when no bush is assigned" do
      expect(media_item.vineyard_name).to be_nil
    end

    it "returns the vineyard name through bush" do
      row  = create(:row, vineyard:, row_number: 1)
      bush = create(:bush, vineyard:, row:, bush_number: 1)
      media_item.bush = bush
      expect(media_item.vineyard_name).to eq(vineyard.name)
    end
  end

  describe "#normalize_filename!" do
    it "returns nil when media is not attached" do
      expect(media_item.normalize_filename!).to be_nil
    end

    it "returns false when filename has no conflict" do
      item = create(:media_item, :with_named_image, folder:, image_filename: "unique.jpg")
      expect(item.normalize_filename!).to be false
    end

    it "renames file when conflict exists and returns true" do
      create(:media_item, :with_named_image, folder:, image_filename: "photo.jpg")
      item = create(:media_item, :with_named_image, folder:, image_filename: "photo.jpg")
      expect(item.normalize_filename!).to be true
      expect(item.media.blob.filename.to_s).to eq("photo(2).jpg")
    end
  end

  describe "#classify!" do
    it "returns false when media is not attached" do
      expect(media_item.classify!).to be false
    end
  end
end
