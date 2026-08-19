require "test_helper"

class SyncNewsRegistryLinksJobTest < ActiveJob::TestCase
  test "syncs registry links over its bounded window" do
    captured = nil

    NewsRegistryLinkService.stub(:sync_recent, ->(days:) { captured = days; {} }) do
      SyncNewsRegistryLinksJob.perform_now
    end

    assert_equal SyncNewsRegistryLinksJob::WINDOW_DAYS, captured
    assert_operator captured, :<, 21,
      "the window bounds resolver spend -- the rake default re-asks the model about three weeks of clusters"
  end

  test "records a failed poll when the sync raises" do
    PollingStat.where(source: "ontology-relationships:news-registry").delete_all

    NewsRegistryLinkService.stub(:sync_recent, ->(days:) { raise "boom" }) do
      assert_raises(RuntimeError) { SyncNewsRegistryLinksJob.perform_now }
    end

    stat = PollingStat.where(source: "ontology-relationships:news-registry").order(created_at: :desc).first
    assert_equal "error", stat.status
  end

  test "is scheduled far slower than the situation build" do
    schedules = GlobalPollerService::JOB_SCHEDULES.index_by { |entry| entry[:job] }
    links = schedules.fetch(SyncNewsRegistryLinksJob)
    build = schedules.fetch(BuildSituationsJob)

    assert_operator links.fetch(:every), :>, build.fetch(:every),
      "registry links spend model calls; the builder is free"
  end
end
