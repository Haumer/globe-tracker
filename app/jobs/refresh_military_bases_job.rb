class RefreshMilitaryBasesJob < ApplicationJob
  queue_as :default

  def perform
    MilitaryBaseRefreshService.refresh_if_stale
  end
end
