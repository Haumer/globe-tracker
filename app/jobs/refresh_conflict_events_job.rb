class RefreshConflictEventsJob < ApplicationJob
  queue_as :default

  def perform
    ConflictEventService.refresh_if_stale
  end
end
