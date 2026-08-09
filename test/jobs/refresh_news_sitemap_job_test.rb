require "test_helper"

class RefreshNewsSitemapJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshNewsSitemapJob.new.queue_name
  end

  test "calls NewsSitemapService.refresh_if_stale" do
    called = false
    NewsSitemapService.stub(:refresh_if_stale, -> { called = true; 0 }) do
      RefreshNewsSitemapJob.perform_now
    end
    assert called, "Expected NewsSitemapService.refresh_if_stale to be called"
  end

  test "is scheduled ahead of enrichment so new articles are geocoded the same cycle" do
    schedules = GlobalPollerService::JOB_SCHEDULES.index_by { |entry| entry[:job] }
    sitemap = schedules.fetch(RefreshNewsSitemapJob)
    enrich = schedules.fetch(EnrichNewsJob)

    assert_equal 5.minutes, sitemap.fetch(:every)
    assert_operator sitemap.fetch(:offset), :<, enrich.fetch(:offset)
  end
end
