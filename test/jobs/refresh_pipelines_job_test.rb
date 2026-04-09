require "test_helper"

class RefreshPipelinesJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshPipelinesJob.new.queue_name
  end

  test "tracks polling with source pipelines and poll_type pipelines" do
    assert_equal "pipelines", RefreshPipelinesJob.polling_source_resolver
    assert_equal "pipelines", RefreshPipelinesJob.polling_type_resolver
  end

  test "calls PipelineRefreshService.refresh_if_stale" do
    called = false
    PipelineRefreshService.stub(:refresh_if_stale, -> { called = true; 8 }) do
      RefreshPipelinesJob.perform_now
    end
    assert called
  end
end
