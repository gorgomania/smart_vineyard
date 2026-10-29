require "rails_helper"

RSpec.describe CloneDemoMediaJob, type: :job do
  let(:master)      { create(:user) }
  let(:demo)        { create(:user, demo_temp: true, demo_expires_at: 1.day.from_now) }
  let(:vineyard)    { create(:vineyard, user: master) }
  let(:row)         { create(:row, vineyard:, row_number: 1) }
  let(:bush)        { create(:bush, vineyard:, row:, bush_number: 1) }
  let(:folder)      { create(:folder, user: master) }
  let(:demo_folder) { create(:folder, user: demo) }
  let(:demo_bush)   { create(:bush, vineyard: create(:vineyard, user: demo), row: create(:row, vineyard: create(:vineyard, user: demo)), bush_number: 1) }

  def perform(bush_map = {})
    described_class.new.perform(demo.id, { folder.id.to_s => demo_folder.id }, bush_map.transform_keys(&:to_s))
  end

  it "copies media items into the mapped folder, sharing the same blobs" do
    item = create(:media_item, :with_image, folder:)
    item.update_columns(ai_class_id: 2, ai_confidence: 0.9)

    perform

    copy = demo_folder.media_items.sole
    expect(copy.media.blob_id).to eq(item.media.blob_id)
    expect(copy.ai_class_id).to eq(2)
    expect(copy.ai_confidence).to eq(0.9)
    expect(ActiveStorage::Blob.count).to eq(1)
  end

  it "maps bush links to the demo bushes and drops unmapped ones" do
    linked   = create(:media_item, :with_named_image, folder:, image_filename: "a.jpg", bush:)
    unmapped = create(:media_item, :with_named_image, folder:, image_filename: "b.jpg")
    unmapped.update_column(:bush_id, create(:bush, vineyard:, row:, bush_number: 2).id)

    perform(bush.id => demo_bush.id)

    copies = demo_folder.media_items.joins(media_attachment: :blob).index_by { |m| m.media.filename.to_s }
    expect(copies["a.jpg"].bush_id).to eq(demo_bush.id)
    expect(copies["b.jpg"].bush_id).to be_nil
    expect(linked.reload.bush_id).to eq(bush.id)
  end

  it "copies video previews too" do
    item = create(:media_item, folder:)
    item.media.attach(io: StringIO.new("fake"), filename: "clip.mp4", content_type: "video/mp4")
    item.video_preview.attach(io: StringIO.new("\xFF\xD8\xFF\xE0fake"), filename: "clip.jpg", content_type: "image/jpeg")

    perform

    copy = demo_folder.media_items.sole
    expect(copy.video_preview.blob_id).to eq(item.video_preview.blob_id)
  end

  it "does nothing when the master folders are empty" do
    expect { perform }.not_to change(MediaItem, :count)
  end
end
