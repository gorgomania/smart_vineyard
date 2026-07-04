class ActiveStorage::DirectUploadsController < ApplicationController
  def create
    blob = ActiveStorage::Blob.create_before_direct_upload!(**blob_args)
    render json: blob.as_json(root: false, methods: :signed_id).merge(
      "direct_upload" => {
        "url" => blob.service_url_for_direct_upload,
        "headers" => blob.service_headers_for_direct_upload
      }
    )
  end

  private

  def blob_args
    params.require(:blob)
          .permit(:filename, :byte_size, :checksum, :content_type, :record_type, :record_id, metadata: {})
          .to_h
          .symbolize_keys
          .merge(metadata: { "user_id" => current_user.id })
  end
end
