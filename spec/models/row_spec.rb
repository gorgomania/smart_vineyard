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

  describe "#free_bushes_label" do
    it "includes row number and free bush count with Russian plural" do
      row = build(:row, row_number: 3)
      expect(row.free_bushes_label(1)).to eq("Ряд 3 (1 свободный куст)")
      expect(row.free_bushes_label(2)).to eq("Ряд 3 (2 свободных куста)")
      expect(row.free_bushes_label(5)).to eq("Ряд 3 (5 свободных кустов)")
    end
  end

  describe ".with_free_bushes" do
    let(:vineyard) { create(:vineyard) }
    let(:full_row) { create(:row, vineyard:, row_number: 1) }
    let(:open_row) { create(:row, vineyard:, row_number: 2) }
    let!(:taken_bush) { create(:bush, vineyard:, row: full_row, bush_number: 1) }

    before do
      create(:bush, vineyard:, row: open_row, bush_number: 1)
      create(:bush, vineyard:, row: open_row, bush_number: 2)
      create(:media_item, bush: taken_bush)
    end

    it "skips rows where every bush is taken and counts only free bushes" do
      expect(Row.with_free_bushes(vineyard)).to eq([ [ open_row, 2 ] ])
    end

    it "treats keep_bush_id as free" do
      expect(Row.with_free_bushes(vineyard, keep_bush_id: taken_bush.id)).to eq([ [ full_row, 1 ], [ open_row, 2 ] ])
    end
  end
end
