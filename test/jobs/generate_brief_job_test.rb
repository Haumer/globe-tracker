require "test_helper"

class GenerateBriefJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", GenerateBriefJob.new.queue_name
  end

  test "calls IntelligenceBriefService.generate with force true" do
    called = false
    mock = ->(**kwargs) { called = true; assert_equal true, kwargs[:force]; nil }

    IntelligenceBriefService.stub(:generate, mock) do
      GenerateBriefJob.perform_now
    end

    assert called, "Expected IntelligenceBriefService.generate to be called"
  end
end
