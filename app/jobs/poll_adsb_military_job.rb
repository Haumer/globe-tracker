class PollAdsbMilitaryJob < ApplicationJob
  queue_as :default

  def perform
    AdsbService.fetch_military
  end
end
