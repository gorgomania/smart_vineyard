require "rails_helper"

RSpec.describe CloneDemoDataJob, type: :job do
  let(:master)      { create(:user) }
  let(:demo)        { create(:user, demo_temp: true, demo_expires_at: 1.day.from_now) }
  let(:vineyard)    { create(:vineyard, user: master) }
  let(:row)         { create(:row, vineyard:, row_number: 1) }
  let(:bush)        { create(:bush, vineyard:, row:, bush_number: 1) }
  let(:folder)      { create(:folder, user: master) }
  let(:demo_folder) { create(:folder, user: demo) }
  # Клон виноградника мастера: его ряды и кусты копирует сама задача
  let(:demo_vineyard) { create(:vineyard, user: demo) }

  def perform(vineyard_map = { vineyard.id => demo_vineyard.id })
    described_class.new.perform(demo.id, { folder.id.to_s => demo_folder.id }, vineyard_map: vineyard_map.transform_keys(&:to_s))
  end

  def layout(of)
    of.bushes.joins(:row).order("rows.row_number", :bush_number).pluck("rows.row_number", :bush_number)
  end

  it "copies rows and bushes with the same numbers" do
    [ 1, 2, 5 ].each do |row_number|
      row = create(:row, vineyard:, row_number:)
      (1..row_number).each { |bush_number| create(:bush, vineyard:, row:, bush_number:) }
    end

    perform

    expect(layout(demo_vineyard)).to eq(layout(vineyard))
    expect(demo_vineyard.rows.count).to eq(3)
  end

  it "copies media items into the mapped folder, sharing the same blobs" do
    item = create(:media_item, :with_image, folder:)
    item.update_columns(ai_class_id: 2, ai_confidence: 0.9, ai_full_results: { "a" => 1 }, ai_classified_at: 1.day.ago)

    perform

    copy = demo_folder.media_items.sole
    expect(copy.media.blob_id).to eq(item.media.blob_id)
    expect(copy.slice(:ai_class_id, :ai_confidence, :ai_full_results)).to eq(item.slice(:ai_class_id, :ai_confidence, :ai_full_results))
    expect(copy.ai_classified_at).to be_within(1.second).of(item.ai_classified_at)
    expect(ActiveStorage::Blob.count).to eq(1)
  end

  it "keeps the order of the files" do
    %w[a b c].each { |name| create(:media_item, :with_named_image, folder:, image_filename: "#{name}.jpg") }

    perform

    expect(demo_folder.media_items.order(:id).map { |item| item.media.filename.to_s }).to eq(%w[a.jpg b.jpg c.jpg])
  end

  it "links copies to the demo bush with the same row and bush number" do
    linked   = create(:media_item, :with_named_image, folder:, image_filename: "a.jpg", bush:)
    unlinked = create(:media_item, :with_named_image, folder:, image_filename: "b.jpg")

    perform

    copies = demo_folder.media_items.index_by { |item| item.media.filename.to_s }
    expect(copies["a.jpg"].bush).to have_attributes(vineyard_id: demo_vineyard.id, bush_number: 1)
    expect(copies["b.jpg"].bush_id).to be_nil
    expect(linked.reload.bush_id).to eq(bush.id)
    expect(unlinked.reload.bush_id).to be_nil
  end

  it "leaves copies unlinked when the master's vineyard was not cloned (deleted by the master)" do
    create(:media_item, :with_image, folder:, bush:)

    perform({})

    expect(demo_folder.media_items.sole.bush_id).to be_nil
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

  # Пользователь уже внутри: без рассылки карта, статистика и папка остались бы пустыми до перезагрузки
  it "refreshes the open map, statistics and folder pages" do
    create(:media_item, :with_image, folder:)
    allow(Vineyard).to receive(:broadcast_diagnoses_changed)

    expect { perform }.to have_broadcasted_to(demo_folder.to_gid_param).with(a_string_including('action="refresh"'))
    expect(Vineyard).to have_received(:broadcast_diagnoses_changed).with([ demo_vineyard.id ])
  end

  # Ряды, кусты и файлы — вместе или никак: иначе повтор упал бы на уникальном индексе рядов
  it "leaves nothing behind when copying fails, so a retry starts clean" do
    bush
    create(:media_item, :with_image, folder:)
    job = described_class.new
    allow(job).to receive(:copy_media_items).and_raise(ActiveRecord::InvalidForeignKey)
    map = { vineyard.id.to_s => demo_vineyard.id }

    expect { job.perform(demo.id, { folder.id.to_s => demo_folder.id }, vineyard_map: map) }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(demo_vineyard.rows).to be_empty

    perform
    expect(demo_folder.media_items.count).to eq(1)
    expect(demo_vineyard.rows.count).to eq(1)
  end
end
