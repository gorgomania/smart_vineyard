
class ActiveStorage::BlobsController < ApplicationController
  skip_after_action :verify_authorized # владельца проверяет сам: blob.metadata["user_id"]

  def destroy
    blob = ActiveStorage::Blob.find_signed(params[:id])

    if blob && !blob.attachments.exists? && blob.metadata["user_id"] == current_user.id
      blob.purge
      head :ok
    else
      head :unprocessable_content
    end
  end
end
