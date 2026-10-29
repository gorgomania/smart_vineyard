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

  it "ignores ids that are already gone" do
    expect { described_class.new.perform([ -1 ]) }.not_to raise_error
  end

  it "splits large lists into batches" do
    ids = (1..1_200).to_a
    expect { described_class.enqueue_in_batches(ids) }.to have_enqueued_job(described_class).exactly(3).times
  end
end
