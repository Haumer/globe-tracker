class RefreshRailwaysJob < ApplicationJob
  queue_as :default

  def perform
    return if Railway.count > 0 # Static dataset — only import once
    RailwayImportService.import!
  end
end
