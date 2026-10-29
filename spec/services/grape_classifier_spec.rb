require "rails_helper"
require "vips"

RSpec.describe GrapeClassifier do
  def image_file(width, height)
    path = Rails.root.join("tmp", "classifier_#{SecureRandom.hex(4)}_#{width}x#{height}.png").to_s
    (Vips::Image.black(width, height, bands: 3) + [ 90, 140, 60 ]).cast(:uchar).write_to_file(path)
    path
  end

  after { Dir[Rails.root.join("tmp", "classifier_*.png")].each { |f| File.delete(f) } }

  describe ".class_names" do
    it "loads the four disease classes" do
      expect(described_class.class_names.size).to eq(4)
    end
  end

  describe ".predict_from_file" do
    it "returns a probability for every class, sorted, summing to 1" do
      result = described_class.predict_from_file(image_file(300, 300))

      expect(result[:predictions].size).to eq(described_class.class_names.size)
      expect(result[:predictions].sum { |p| p[:probability] }).to be_within(1e-6).of(1.0)
      expect(result[:predictions].map { |p| p[:probability] }).to eq(result[:predictions].map { |p| p[:probability] }.sort.reverse)
      expect(result[:top_class]).to eq(described_class.class_names[result[:class_id]])
      expect(result[:confidence]).to eq(result[:predictions].first[:probability])
    end

    # Ресайз до 224 по короткой стороне + центральный кроп: проверяем неудобные пропорции и размеры
    [ [ 224, 224 ], [ 225, 224 ], [ 333, 500 ], [ 1000, 301 ], [ 100, 37 ] ].each do |w, h|
      it "handles a #{w}x#{h} image" do
        expect(described_class.predict_from_file(image_file(w, h))[:predictions].size).to eq(4)
      end
    end
  end

  describe ".predict_from_media_item" do
    let(:media_item) { create(:media_item) }

    it "raises when nothing is attached" do
      expect { described_class.predict_from_media_item(media_item) }.to raise_error(ArgumentError, /no attached file/)
    end

    it "raises for a video" do
      media_item.media.attach(io: StringIO.new("fake"), filename: "clip.mp4", content_type: "video/mp4")
      expect { described_class.predict_from_media_item(media_item) }.to raise_error(ArgumentError, /not an image/)
    end

    it "classifies an attached image" do
      media_item.media.attach(io: File.open(image_file(400, 300)), filename: "leaf.png", content_type: "image/png")
      expect(described_class.predict_from_media_item(media_item)[:class_id]).to be_between(0, 3)
    end
  end
end
