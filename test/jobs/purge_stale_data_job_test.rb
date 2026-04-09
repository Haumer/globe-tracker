require "test_helper"

class PurgeStaleDataJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", PurgeStaleDataJob.new.queue_name
  end

  test "runs without error" do
    # The job calls delete_all on multiple models; just verify it runs
    assert_nothing_raised do
      PurgeStaleDataJob.perform_now
    end
  end
end
