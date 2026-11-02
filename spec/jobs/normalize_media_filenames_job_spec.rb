require "rails_helper"

RSpec.describe NormalizeMediaFilenamesJob, type: :job do
  let(:folder) { create(:folder, user: create(:user)) }

  describe "#perform" do
    it "does not raise for valid media items" do
      items = create_list(:media_item, 2, :with_image, folder:)
      expect { described_class.new.perform(items.map(&:id)) }.not_to raise_error
    end

    it "calls normalize_filename! on each media_item" do
      items = create_list(:media_item, 2, :with_image, folder:)
      call_count = 0
      allow_any_instance_of(MediaItem).to receive(:normalize_filename!) { call_count += 1; false }
      described_class.new.perform(items.map(&:id))
      expect(call_count).to eq(2)
    end
  end

  describe "a batch" do
    def item(name) = create(:media_item, :with_named_image, folder:, image_filename: name)

    it "loads the folder's names once for the whole batch, not once per file" do
      items = 3.times.map { |i| item("p#{i}.jpg") }
      expect(MediaItem).to receive(:filenames_in_folder).once.and_call_original
      described_class.new.perform(items.map(&:id))
    end

    it "keeps names taken by files outside the batch and lets the first of two equal names keep it" do
      item("photo.jpg")
      first = item("photo.jpg")
      second = item("photo.jpg")

      described_class.new.perform([ first.id, second.id ])
      expect([ first, second ].map { |i| i.reload.media.blob.filename.to_s }).to eq([ "photo(2).jpg", "photo(3).jpg" ])
    end

    it "dedupes inside the batch" do
      a = item("same.jpg")
      b = item("same.jpg")

      described_class.new.perform([ a.id, b.id ])
      expect([ a, b ].map { |i| i.reload.media.blob.filename.to_s }).to eq([ "same.jpg", "same(2).jpg" ])
    end
  end
end
