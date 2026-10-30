class RefreshFolderJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError # папку успели удалить

  def perform(folder)
    folder.broadcast_refresh
  end
end
