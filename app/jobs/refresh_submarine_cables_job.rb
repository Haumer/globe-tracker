class RefreshSubmarineCablesJob < ApplicationJob
  queue_as :default

  def perform
    SubmarineCableRefreshService.refresh_if_stale
  end
end
