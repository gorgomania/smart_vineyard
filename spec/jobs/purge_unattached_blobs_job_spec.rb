require "rails_helper"

RSpec.describe PurgeUnattachedBlobsJob, type: :job do
  def blob
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new("data"), filename: "f.jpg", content_type: "image/jpeg")
  end

  it "purges blobs without attachments and keeps attached ones" do
    orphan = blob
    attached = create(:media_item, :with_image).media.blob

    described_class.new.perform([ orphan.id, attached.id ])

    expect(ActiveStorage::Blob.exists?(orphan.id)).to be false
    expect(ActiveStorage::Blob.service.exist?(orphan.key)).to be false
    expect(ActiveStorage::Blob.exists?(attached.id)).to be true
  end

  it "removes thumbnails with their files in bulk, without enqueueing a job per thumbnail" do
    jpeg = Vips::Image.black(40, 30).add(120).cast(:uchar).jpegsave_buffer
    orphan = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(jpeg), filename: "p.jpg", content_type: "image/jpeg")
    thumb = orphan.variant(resize_to_limit: [ 20, 20 ]).processed.image.blob

    expect {
      described_class.new.perform([ orphan.id ])
    }.not_to have_enqueued_job

    expect(ActiveStorage::Blob.where(id: [ orphan.id, thumb.id ])).to be_empty
    expect(ActiveStorage::VariantRecord.where(blob_id: orphan.id)).to be_empty
    expect(ActiveStorage::Attachment.where(blob_id: thumb.id)).to be_empty
    expect(ActiveStorage::Blob.service.exist?(orphan.key)).to be false
    expect(ActiveStorage::Blob.service.exist?(thumb.key)).to be false
  end

  it "ignores ids that are already gone" do
    expect { described_class.new.perform([ -1 ]) }.not_to raise_error
  end

  it "splits large lists into batches" do
    ids = (1..1_200).to_a
    expect { described_class.enqueue_in_batches(ids) }.to have_enqueued_job(described_class).exactly(3).times
  end
end
