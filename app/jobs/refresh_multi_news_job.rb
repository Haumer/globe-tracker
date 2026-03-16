class RefreshMultiNewsJob < ApplicationJob
  queue_as :default

  def perform
    MultiNewsService.refresh_if_stale
  end
end
