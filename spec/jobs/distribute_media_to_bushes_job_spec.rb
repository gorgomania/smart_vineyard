require "rails_helper"

RSpec.describe DistributeMediaToBushesJob, type: :job do
  let(:user)     { create(:user) }
  let(:vineyard) { create(:vineyard, user:) }
  let(:folder)   { create(:folder, user:, vineyard:) }
  let(:row)      { create(:row, vineyard:, row_number: 1) }
  let!(:bush)    { create(:bush, vineyard:, row:, bush_number: 1) }

  def named_item(filename, **attrs)
    create(:media_item, :with_named_image, folder:, image_filename: filename, **attrs)
  end

  describe "#perform" do
    context "when folder does not exist" do
      it "returns without raising" do
        expect { described_class.new.perform(-1) }.not_to raise_error
      end
    end

    context "when media_item_ids is empty" do
      it "returns without raising" do
        expect { described_class.new.perform(folder.id, []) }.not_to raise_error
      end
    end

    context "when filename matches a bush" do
      it "assigns the correct bush for the whole folder" do
        item = named_item("Ряд 1 Куст 1.jpg")
        described_class.new.perform(folder.id)
        expect(item.reload.bush_id).to eq(bush.id)
      end

      it "assigns only the given items" do
        create(:bush, vineyard:, row:, bush_number: 2)
        item = named_item("ряд 1 куст 1.jpg")
        skipped = named_item("Ряд 1 Куст 2.jpg")
        described_class.new.perform(folder.id, [ item.id ])
        expect(item.reload.bush_id).to eq(bush.id)
        expect(skipped.reload.bush_id).to be_nil
      end
    end

    context "when filename does not match the pattern" do
      it "does not assign a bush" do
        item = named_item("img_001.jpg")
        described_class.new.perform(folder.id)
        expect(item.reload.bush_id).to be_nil
      end
    end

    context "when two files point to the same bush" do
      it "assigns the bush to the first file only" do
        first  = named_item("Ряд 1 Куст 1.jpg")
        second = named_item("Ряд 1 Куст 1(2).jpg")

        expect { described_class.new.perform(folder.id) }.not_to raise_error
        expect(first.reload.bush_id).to eq(bush.id)
        expect(second.reload.bush_id).to be_nil
      end
    end

    context "when folder has no vineyard (detached)" do
      it "unassigns named files and keeps manually assigned ones" do
        named  = named_item("Ряд 1 Куст 1.jpg")
        manual = named_item("photo.jpg")
        named.update_columns(bush_id: bush.id)
        manual_bush = create(:bush, vineyard:, row:, bush_number: 2)
        manual.update_columns(bush_id: manual_bush.id)
        folder.update!(vineyard: nil)

        described_class.new.perform(folder.id)

        expect(named.reload.bush_id).to be_nil
        expect(manual.reload.bush_id).to eq(manual_bush.id)
      end
    end

    context "when folder is moved to another vineyard" do
      let(:old_vineyard) { create(:vineyard, user:) }
      let(:old_bush)     { create(:bush, vineyard: old_vineyard, row: create(:row, vineyard: old_vineyard, row_number: 8), bush_number: 3) }

      it "unassigns a named file whose bush is missing in the new vineyard" do
        item = named_item("Ряд 8 Куст 3.jpg")
        item.update_columns(bush_id: old_bush.id)

        described_class.new.perform(folder.id)

        expect(item.reload.bush_id).to be_nil
      end

      it "keeps a manually assigned file untouched" do
        item = named_item("photo.jpg")
        item.update_columns(bush_id: old_bush.id)

        described_class.new.perform(folder.id)

        expect(item.reload.bush_id).to eq(old_bush.id)
      end
    end

    context "when the bush is held by a manually assigned file" do
      it "does not take it away" do
        manual = named_item("photo.jpg")
        manual.update_columns(bush_id: bush.id)
        item = named_item("Ряд 1 Куст 1.jpg")

        described_class.new.perform(folder.id)

        expect(manual.reload.bush_id).to eq(bush.id)
        expect(item.reload.bush_id).to be_nil
      end
    end

    context "when two files swap bushes after rename" do
      it "swaps without hitting the unique index" do
        bush2 = create(:bush, vineyard:, row:, bush_number: 2)
        a = named_item("Ряд 1 Куст 1.jpg")
        b = named_item("Ряд 1 Куст 2.jpg")
        a.update_columns(bush_id: bush2.id)
        b.update_columns(bush_id: bush.id)

        described_class.new.perform(folder.id)

        expect(a.reload.bush_id).to eq(bush.id)
        expect(b.reload.bush_id).to eq(bush2.id)
      end
    end
  end
end
