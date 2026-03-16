class RefreshAcledJob < ApplicationJob
  queue_as :default

  def perform
    AcledService.refresh_if_stale
  end
end
