class ActiveStorageBlobsController < ApplicationController
  def destroy
    blob = ActiveStorage::Blob.find_signed(params[:id])

    if blob && !blob.attachments.exists?
      blob.purge
      head :ok
    else
      head :unprocessable_entity
    end
  end
end
