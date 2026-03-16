class GenerateBriefJob < ApplicationJob
  queue_as :default

  def perform
    IntelligenceBriefService.generate(force: true)
  end
end
