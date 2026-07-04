
class ActiveStorage::BlobsController < ApplicationController
  def destroy
    blob = ActiveStorage::Blob.find_signed(params[:id])

    if blob && !blob.attachments.exists? && blob.metadata["user_id"] == current_user.id
      blob.purge
      head :ok
    else
      head :unprocessable_entity
    end
  end
end
