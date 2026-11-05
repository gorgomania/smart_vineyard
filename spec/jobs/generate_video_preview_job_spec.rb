require "rails_helper"

RSpec.describe GenerateVideoPreviewJob, type: :job do
  let(:item) { create(:media_item) }

  def attach_video(io)
    item.media.attach(io:, filename: "clip.mp4", content_type: "video/mp4")
  end

  # ffmpeg пишет ход работы в stderr: перехватываем, чтобы не сыпался в вывод тестов
  def perform_quietly
    expect { described_class.perform_now(item.id) }.to output.to_stderr_from_any_process
  end

  describe "#perform" do
    context "with a real video" do
      before { attach_video(File.open(Rails.root.join("spec/fixtures/files/clip.mp4"))) }

      it "attaches a frame of the video as a JPEG preview" do
        perform_quietly

        preview = item.reload.video_preview
        expect(preview.filename.to_s).to eq("preview_clip.jpg")
        expect(preview.content_type).to eq("image/jpeg")
        frame = Vips::Image.new_from_buffer(preview.download, "")
        expect([ frame.width, frame.height ]).to eq([ 64, 48 ])
      end

      it "replaces the placeholder on the open folder page" do
        expect { perform_quietly }.to have_broadcasted_to(MediaItem.preview_stream(item.folder_id))
          .with(a_string_including(%(target="video-preview-#{item.id}"), "<img"))
      end

      it "leaves no temporary file behind" do
        perform_quietly
        expect(Rails.root.join("tmp", "preview_#{item.id}.jpg")).not_to exist
      end
    end

    context "when ffmpeg cannot read the file" do
      before { attach_video(StringIO.new("not a video")) }

      it "attaches nothing and does not broadcast" do
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
        perform_quietly

        expect(item.reload.video_preview).not_to be_attached
        expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
      end
    end

    context "when media_item does not exist" do
      it "is discarded without raising" do
        expect { described_class.perform_now(-1) }.not_to raise_error
      end
    end
  end
end
