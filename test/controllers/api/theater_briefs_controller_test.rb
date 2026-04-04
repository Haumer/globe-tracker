require "test_helper"

class Api::TheaterBriefsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
    Rails.cache.clear
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
    Rails.cache.clear
  end

  test "show returns a stored theater brief when one exists for the current zone signature" do
    zone = sample_zone
    persist_conflict_pulse_snapshot(zone)

    LayerSnapshot.create!(
      snapshot_type: TheaterBriefService::SNAPSHOT_TYPE,
      scope_key: TheaterBriefService.scope_key_for(zone),
      status: "ready",
      payload: {
        brief: {
          assessment: "Stored assessment for the selected theater.",
          key_developments: ["Development one"],
          watch_next: ["Watch item one"],
          confidence_level: "high",
          confidence_rationale: "Stored rationale.",
        },
      },
      metadata: {
        provider: "test",
        model: "stub",
        source_context: { theater: zone[:theater] },
      },
      fetched_at: Time.current,
    )

    get "/api/theater_brief", params: { theater: zone[:theater], cell_key: zone[:cell_key] }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "ready", body["status"]
    assert_equal "Stored assessment for the selected theater.", body.dig("brief", "assessment")
    assert_equal "test", body["provider"]
  end

  test "show enqueues generation and returns pending when no stored brief exists" do
    zone = sample_zone
    persist_conflict_pulse_snapshot(zone)

    assert_enqueued_with(job: GenerateTheaterBriefJob) do
      get "/api/theater_brief", params: { theater: zone[:theater], cell_key: zone[:cell_key] }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "pending", body["status"]

    snapshot = LayerSnapshot.find_by!(
      snapshot_type: TheaterBriefService::SNAPSHOT_TYPE,
      scope_key: TheaterBriefService.scope_key_for(zone)
    )
    assert_equal "pending", snapshot.status
  end

  private

  def persist_conflict_pulse_snapshot(zone)
    LayerSnapshot.create!(
      snapshot_type: "conflict_pulse",
      scope_key: "global",
      status: "ready",
      payload: { zones: [zone], strategic_situations: [], strike_arcs: [], hex_cells: [] },
      fetched_at: Time.current,
      expires_at: 5.minutes.from_now,
    )
  end

  def sample_zone
    {
      theater: "Middle East / Iran War",
      cell_key: "25,55",
      situation_name: "Strait of Hormuz",
      pulse_score: 81,
      escalation_trend: "surging",
      count_24h: 5,
      source_count: 4,
      story_count: 5,
      spike_ratio: 7.0,
      avg_tone: -3.6,
      cross_layer_signals: { military_flights: 8, gps_jamming: 27 },
      top_articles: [
        {
          title: "War in the Middle East: UNSC vote on Strait of Hormuz postponed",
          publisher: "France 24",
          published_at: 2.hours.ago.iso8601,
          cluster_id: "cluster:hormuz",
        },
      ],
      top_headlines: ["War in the Middle East: UNSC vote on Strait of Hormuz postponed"],
      detected_at: Time.current.iso8601,
    }
  end
end
