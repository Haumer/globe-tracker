require "test_helper"

class InternetOutageRefreshServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
    Rails.cache.clear
    OperationalOntologySyncService.instance_variable_set(:@recent_enqueue_slots, {})
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
    Rails.cache.clear
    OperationalOntologySyncService.instance_variable_set(:@recent_enqueue_slots, {})
  end

  test "IODA_BASE is correct" do
    assert_equal "https://api.ioda.inetintel.cc.gatech.edu/v2", InternetOutageRefreshService::IODA_BASE
  end

  test "outage_level classifies scores correctly" do
    svc = InternetOutageRefreshService.new
    assert_equal "critical", svc.send(:outage_level, 150_000)
    assert_equal "severe", svc.send(:outage_level, 50_000)
    assert_equal "moderate", svc.send(:outage_level, 5_000)
    assert_equal "minor", svc.send(:outage_level, 500)
  end

  test "summary_cache_path returns tmp path" do
    path = InternetOutageRefreshService.summary_cache_path
    assert path.to_s.include?("tmp/internet_outage_summary.json")
  end

  test "cached_summary returns array" do
    result = InternetOutageRefreshService.cached_summary
    assert_instance_of Array, result
  end

  test "upsert_events enqueues operational ontology sync" do
    svc = InternetOutageRefreshService.new
    now = Time.zone.parse("2026-03-25 12:00:00 UTC")
    events_data = [
      {
        "entity" => { "type" => "country", "code" => "IR", "name" => "Iran" },
        "datasource" => "cloudflare",
        "score" => 78_000,
        "method" => "disruption",
        "from" => now.to_i - 300,
        "until" => nil,
      },
    ]

    assert_enqueued_with(job: OperationalOntologyBatchJob) do
      assert_equal 1, svc.send(:upsert_events, events_data, now)
    end
  end
end
