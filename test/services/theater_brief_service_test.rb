require "test_helper"

class TheaterBriefServiceTest < ActiveSupport::TestCase
  test "refresh persists a structured theater brief snapshot" do
    zone = sample_zone
    scope_key = TheaterBriefService.scope_key_for(zone)

    original = TheaterBriefService.method(:generate_brief_payload)
    TheaterBriefService.define_singleton_method(:generate_brief_payload) do |_zone|
      {
        assessment: "Escalation remains concentrated around Hormuz with corroborating reporting.",
        why_we_believe_it: ["Five recent reports from four sources are carrying the theater."],
        key_developments: ["Fresh shipping disruption reporting is leading the cycle."],
        watch_next: ["Additional flight or jamming activity would reinforce escalation."],
        confidence_level: "high",
        confidence_rationale: "Source depth and cluster density are both elevated.",
        provider: "test",
        model: "stub-model",
      }
    end

    begin
      snapshot = TheaterBriefService.refresh(scope_key:, zone_payload: zone, force: true)

      assert_equal "ready", snapshot.status
      assert_equal "Escalation remains concentrated around Hormuz with corroborating reporting.", snapshot.payload.dig("brief", "assessment")
      assert_equal ["Five recent reports from four sources are carrying the theater."], snapshot.payload.dig("brief", "why_we_believe_it")
      assert_equal ["Fresh shipping disruption reporting is leading the cycle."], snapshot.payload.dig("brief", "key_developments")
      assert_equal "test", snapshot.metadata["provider"]
      assert_equal "stub-model", snapshot.metadata["model"]
      assert_equal "Middle East / Iran War", snapshot.metadata.dig("source_context", "theater")
      assert_nil snapshot.expires_at
    ensure
      TheaterBriefService.define_singleton_method(:generate_brief_payload, original)
    end
  end

  test "public order theater prompts suppress kinetic thermal signals" do
    zone = {
      theater: "Europe",
      cell_key: "50,-2",
      situation_name: "United Kingdom",
      analysis_context: "public_order_or_security",
      pulse_score: 80,
      escalation_trend: "escalating",
      count_24h: 9,
      source_count: 7,
      story_count: 8,
      spike_ratio: 3.0,
      avg_tone: -5.7,
      cross_layer_signals: {
        military_flights: 4,
        strike_signals_7d: 2704,
        fire_hotspots: 12,
      },
      top_articles: [
        {
          title: "Man arrested after crash causes rush hour disruption in Bolton",
          publisher: "Local outlet",
          published_at: 2.hours.ago.iso8601,
        },
      ],
      detected_at: Time.current.iso8601,
    }

    prompt = TheaterBriefService.send(:build_prompt, zone)

    assert_includes prompt, "Analytic context: public_order_or_security"
    assert_includes prompt, "- nearby military flights count: 4"
    refute_includes prompt, "strike signals 7d"
    refute_includes prompt, "fire hotspots"
    assert_includes prompt, "Do NOT use war, battlefield, strike, operational-tempo, preparatory, or destabilization language"
  end

  private

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
      analysis_context: "kinetic_conflict",
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
