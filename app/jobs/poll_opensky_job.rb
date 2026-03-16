class PollOpenskyJob < ApplicationJob
  queue_as :default

  def perform
    OpenskyService.fetch_flights(bounds: {})
  end
end
