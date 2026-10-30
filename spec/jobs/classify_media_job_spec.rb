require "rails_helper"

RSpec.describe ClassifyMediaJob, type: :job do
  describe "#perform" do
    context "when media_item does not exist" do
      it "returns without raising" do
        expect { described_class.new.perform(-1) }.not_to raise_error
      end
    end

    context "when media is not attached" do
      it "returns false from classify!" do
        item = create(:media_item)
        expect(described_class.new.perform(item.id)).to be_falsy
      end
    end

    context "when media is attached" do
      it "calls classify! on the media_item" do
        item = create(:media_item, :with_image)
        expect_any_instance_of(MediaItem).to receive(:classify!).and_return(true)
        described_class.new.perform(item.id)
      end
    end

    context "when the classified media is attached to a bush" do
      it "repaints that bush on the vineyard heatmap" do
        vineyard = create(:vineyard)
        row = create(:row, vineyard:, row_number: 3)
        item = create(:media_item, :with_image, bush: create(:bush, vineyard:, row:, bush_number: 7))
        allow(GrapeClassifier).to receive(:predict_from_media_item)
          .and_return(class_id: 2, confidence: 0.99, predictions: [])

        allow(Turbo::StreamsChannel).to receive(:broadcast_action_to)

        described_class.new.perform(item.id)
        expect(Turbo::StreamsChannel).to have_received(:broadcast_action_to).with(
          vineyard, :heatmap,
          hash_including(action: :heatmap_bush, target: "map",
                         attributes: { bush: "3-7", "media-item-id": item.id, "class-id": 2 })
        )
      end
    end

    context "when media is a video" do
      it "skips classification without failing and refreshes the panel" do
        item = create(:media_item)
        item.media.attach(io: StringIO.new("fake"), filename: "clip.mp4", content_type: "video/mp4")
        expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
          .with("media_item_#{item.id}", hash_including(target: "analysis-panel-#{item.id}"))

        expect { described_class.new.perform(item.id) }.not_to raise_error
        expect(item.reload.ai_class_id).to be_nil
      end
    end
  end
end
