class GenerateBriefJob < ApplicationJob
  queue_as :background

  def perform
    IntelligenceBriefService.generate(force: true)
  end
end
