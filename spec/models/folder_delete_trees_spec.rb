require "rails_helper"

RSpec.describe Folder, ".delete_trees!" do
  include ActiveJob::TestHelper

  let(:user)  { create(:user) }
  let(:root)  { create(:folder, user:, title: "Root") }
  let(:child) { create(:folder, user:, parent: root, title: "Child") }
  let(:deep)  { create(:folder, user:, parent: child, title: "Deep") }

  def image_item(folder, name)
    create(:media_item, :with_named_image, folder:, image_filename: name)
  end

  it "deletes the whole subtree with its media items and attachments" do
    items = [ image_item(root, "a.jpg"), image_item(child, "b.jpg"), image_item(deep, "c.jpg") ]
    sibling = create(:folder, user:, title: "Sibling")
    kept = image_item(sibling, "kept.jpg")

    root.delete_tree!

    expect(Folder.where(id: [ root.id, child.id, deep.id ])).to be_empty
    expect(MediaItem.where(id: items.map(&:id))).to be_empty
    expect(ActiveStorage::Attachment.where(record_type: "MediaItem", record_id: items.map(&:id))).to be_empty
    expect(sibling.reload).to be_present
    expect(kept.reload.media).to be_attached
  end

  it "enqueues file purging after commit and the job removes the files and previews" do
    item = create(:media_item, folder: deep)
    jpeg = Vips::Image.black(300, 200, bands: 3).jpegsave_buffer
    item.media.attach(io: StringIO.new(jpeg), filename: "a.jpg", content_type: "image/jpeg")
    blob = item.media.blob
    item.media.variant(resize_to_limit: [ 132, 88 ]).processed
    variant_blob_ids = ActiveStorage::VariantRecord.where(blob_id: blob.id).joins(:image_attachment).pluck("active_storage_attachments.blob_id")

    expect { root.delete_tree! }.to have_enqueued_job(PurgeUnattachedBlobsJob).with([ blob.id ])

    perform_enqueued_jobs { perform_enqueued_jobs } # purge ставит PurgeJob для блоба превью
    expect(ActiveStorage::Blob.where(id: [ blob.id, *variant_blob_ids ])).to be_empty
    expect(ActiveStorage::Blob.service.exist?(blob.key)).to be false
  end

  it "keeps files that are still shared with another record (demo copy)" do
    item = image_item(child, "shared.jpg")
    blob = item.media.blob
    other = create(:media_item, folder: create(:folder, user: create(:user)))
    ActiveStorage::Attachment.create!(name: "media", record: other, blob:)

    perform_enqueued_jobs { root.delete_tree! }

    expect(ActiveStorage::Blob.exists?(blob.id)).to be true
    expect(other.reload.media).to be_attached
  end

  it "unlinks the vineyard but keeps it" do
    vineyard = create(:vineyard, user:)
    child.update!(vineyard:)

    root.delete_tree!

    expect(vineyard.reload).to be_present
    expect(Folder.where(vineyard_id: vineyard.id)).to be_empty
  end

  it "does nothing for an empty list" do
    expect { described_class.delete_trees!([]) }.not_to change(Folder, :count)
  end
end
