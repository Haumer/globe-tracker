require "test_helper"

class ConflictPulseServiceTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
  end

  test "returns empty array with no conflict news" do
    data = ConflictPulseService.analyze; result = data[:zones] || []
    assert_equal [], result
  end

  test "detects pulse zone from clustered conflict news" do
    cluster = NewsStoryCluster.create!(
      cluster_key: "cluster:conflict-pulse",
      canonical_title: "Fighting escalates",
      content_scope: "core",
      event_family: "conflict",
      event_type: "military_activity",
      location_name: "Region",
      latitude: 49.1,
      longitude: 35.1,
      geo_precision: "point",
      first_seen_at: 10.hours.ago,
      last_seen_at: 1.hour.ago,
      article_count: 10,
      source_count: 5,
      cluster_confidence: 0.82,
      verification_status: "multi_source",
      source_reliability: 0.77,
      geo_confidence: 0.81
    )

    10.times do |i|
      NewsEvent.create!(
        url: "https://example.com/conflict-#{i}",
        title: "Fighting escalates in region #{i}",
        latitude: 49.0 + rand * 0.5,
        longitude: 35.0 + rand * 0.5,
        tone: -5.0 - rand,
        category: "conflict",
        credibility: "tier2/low",
        source: ["reuters", "bbc", "aljazeera", "cnn", "guardian"][i % 5],
        story_cluster_id: cluster.cluster_key,
        published_at: (i * 2).hours.ago,
        fetched_at: Time.current,
      )
    end

    data = ConflictPulseService.analyze; result = data[:zones] || []

    assert result.any?, "Should detect at least one pulse zone"
    zone = result.first
    assert zone[:pulse_score] >= 20
    assert_includes %w[surging escalating elevated baseline], zone[:escalation_trend]
    assert zone[:count_24h] > 0
    assert zone[:top_headlines].any?
    assert_equal cluster.cluster_key, zone.dig(:top_articles, 0, :cluster_id)
    assert zone[:source_count] > 1
  end

  test "filters out cells with fewer than MIN_ARTICLES or single source" do
    2.times do |i|
      NewsEvent.create!(
        url: "https://example.com/sparse-#{i}",
        title: "Minor incident #{i}",
        latitude: -30.0,
        longitude: 25.0,
        tone: -4.0,
        category: "conflict",
        source: "reuters",
        published_at: i.hours.ago,
        fetched_at: Time.current,
      )
    end

    result = ConflictPulseService.new.compute
    assert_empty result
  end

  test "spike ratio increases score when frequency surges" do
    # Baseline: 1 article per day for 5 days (multi-source)
    5.times do |i|
      NewsEvent.create!(
        url: "https://example.com/base-#{i}",
        title: "Ongoing tension #{i}",
        latitude: 15.0,
        longitude: 45.0,
        tone: -3.0,
        category: "conflict",
        credibility: "tier2/low",
        source: ["reuters", "bbc"][i % 2],
        published_at: (2 + i).days.ago,
        fetched_at: Time.current,
      )
    end

    # Surge: 8 articles today from multiple sources
    8.times do |i|
      NewsEvent.create!(
        url: "https://example.com/surge-#{i}",
        title: "Major escalation event #{i}",
        latitude: 15.0 + rand * 0.3,
        longitude: 45.0 + rand * 0.3,
        tone: -6.0 - rand,
        category: "conflict",
        credibility: "tier1/low",
        source: ["reuters", "bbc", "aljazeera", "france24"][i % 4],
        published_at: (i * 2).hours.ago,
        fetched_at: Time.current,
      )
    end

    data = ConflictPulseService.analyze; result = data[:zones] || []
    assert result.any?
    zone = result.first
    assert zone[:spike_ratio] > 2.0, "Spike ratio should reflect frequency surge"
    assert_includes %w[surging escalating], zone[:escalation_trend]
  end

  test "cross-layer signals boost score" do
    5.times do |i|
      NewsEvent.create!(
        url: "https://example.com/cross-#{i}",
        title: "Conflict with military activity #{i}",
        latitude: 50.0,
        longitude: 35.0,
        tone: -4.0,
        category: "conflict",
        credibility: "tier2/low",
        source: ["reuters", "bbc", "cnn"][i % 3],
        published_at: (i * 3).hours.ago,
        fetched_at: Time.current,
      )
    end

    # Add military flights in the same area
    3.times do |i|
      Flight.create!(
        icao24: "pulse-mil-#{i}",
        callsign: "FORTE#{i}",
        latitude: 50.5,
        longitude: 35.5,
        altitude: 40000,
        origin_country: "US",
        military: true,
      )
    end

    FireHotspot.create!(
      external_id: "pulse-strike-001",
      latitude: 50.2,
      longitude: 35.2,
      brightness: 351.0,
      confidence: "high",
      satellite: "Aqua",
      instrument: "MODIS",
      frp: 60.0,
      daynight: "N",
      acq_datetime: 12.hours.ago,
      fetched_at: Time.current
    )

    data = ConflictPulseService.analyze; result = data[:zones] || []
    assert result.any?
    zone = result.first
    assert zone[:cross_layer_signals][:military_flights], "Should detect military flights"
    assert_equal 1, zone[:cross_layer_signals][:strike_signals_7d]
    assert_equal "kinetic_conflict", zone[:analysis_context]
  end

  test "does not treat thermal detections as strike signals in public order contexts" do
    5.times do |i|
      NewsEvent.create!(
        url: "https://example.com/uk-public-order-#{i}",
        title: "Public order disruption in Bolton #{i}",
        latitude: 51.0,
        longitude: -1.0,
        tone: -5.0,
        category: "conflict",
        credibility: "tier4/low",
        source: ["local-a", "local-b", "local-c"][i % 3],
        published_at: (i * 2).hours.ago,
        fetched_at: Time.current,
      )
    end

    FireHotspot.create!(
      external_id: "pulse-public-order-fire-001",
      latitude: 51.1,
      longitude: -1.1,
      brightness: 351.0,
      confidence: "high",
      satellite: "Aqua",
      instrument: "MODIS",
      frp: 60.0,
      daynight: "N",
      acq_datetime: 12.hours.ago,
      fetched_at: Time.current
    )

    data = ConflictPulseService.analyze
    zone = (data[:zones] || []).find { |candidate| candidate[:situation_name] == "United Kingdom" }

    assert zone, "Should detect the public order cluster"
    assert_equal "public_order_or_security", zone[:analysis_context]
    assert_nil zone[:cross_layer_signals][:strike_signals_7d]
    assert_nil zone[:cross_layer_signals][:fire_hotspots]
  end

  test "does not cluster ingested records with untrusted stored coordinates" do
    source = NewsSource.create!(canonical_key: "untrusted-source", name: "Untrusted Source", source_kind: "wire")

    5.times do |i|
      article = NewsArticle.create!(
        news_source: source,
        url: "https://example.com/untrusted-#{i}",
        canonical_url: "https://example.com/untrusted-#{i}",
        title: "Unclear security update #{i}",
        normalization_status: "normalized"
      )
      NewsEvent.create!(
        news_source: source,
        news_article: article,
        url: article.url,
        title: article.title,
        latitude: 43.0,
        longitude: -81.0,
        tone: -5.0,
        category: "conflict",
        credibility: "tier2/low",
        source: ["wire-a", "wire-b", "wire-c"][i % 3],
        published_at: (i * 2).hours.ago,
        fetched_at: Time.current
      )
    end

    data = ConflictPulseService.analyze
    assert_empty data[:zones] || []
  end

  test "uses title event location over bad stored coordinates" do
    source = NewsSource.create!(canonical_key: "london-wire", name: "London Wire", source_kind: "wire")

    5.times do |i|
      article = NewsArticle.create!(
        news_source: source,
        url: "https://example.com/london-#{i}",
        canonical_url: "https://example.com/london-#{i}",
        title: "London police arrest protesters #{i}",
        normalization_status: "normalized"
      )
      NewsEvent.create!(
        news_source: source,
        news_article: article,
        url: article.url,
        title: article.title,
        latitude: 43.0,
        longitude: -81.0,
        tone: -5.0,
        category: "unrest",
        credibility: "tier2/low",
        source: ["wire-a", "wire-b", "wire-c"][i % 3],
        published_at: (i * 2).hours.ago,
        fetched_at: Time.current
      )
    end

    data = ConflictPulseService.analyze
    zones = data[:zones] || []
    london = zones.find { |zone| zone[:situation_name] == "United Kingdom" }

    assert london, "Expected London UK title location to create a UK public-order zone"
    assert_in_delta 51.0, london[:lat], 0.1
    assert_in_delta(-1.0, london[:lng], 0.1)
    refute zones.any? { |zone| zone[:lat] == 43.0 && zone[:lng] == -81.0 }
  end

  test "does not classify generic European drone incidents as kinetic conflict" do
    article = Struct.new(:title).new("Drone sighting over Denmark disrupts airport operations")

    result = ConflictPulseService.new.send(
      :kinetic_conflict_context?,
      theater: "Europe",
      situation_name: "Denmark",
      articles: [article]
    )

    refute result
  end

  test "caches results when cache store supports it" do
    cache = ActiveSupport::Cache::MemoryStore.new
    5.times do |i|
      NewsEvent.create!(
        url: "https://example.com/cache-#{i}",
        title: "Cached conflict #{i}",
        latitude: 10.0, longitude: 10.0,
        tone: -4.0, category: "conflict",
        credibility: "tier1/low",
        source: ["reuters", "bbc", "cnn"][i % 3],
        published_at: i.hours.ago,
        fetched_at: Time.current,
      )
    end

    first = cache.fetch(ConflictPulseService::CACHE_KEY, expires_in: 10.minutes) { ConflictPulseService.new.compute }
    assert first.any?

    NewsEvent.delete_all
    second = cache.fetch(ConflictPulseService::CACHE_KEY, expires_in: 10.minutes) { ConflictPulseService.new.compute }
    assert_equal first, second
  end

  test "promotes a strategic Hormuz marker when named reporting is strong but local pulse cell is absent" do
    source = NewsSource.create!(canonical_key: "test-source", name: "Test Source", source_kind: "wire")

    iran_cluster = NewsStoryCluster.create!(
      cluster_key: "cluster:iran-war",
      canonical_title: "Iran war escalation around Tehran",
      content_scope: "core",
      event_family: "conflict",
      event_type: "military_activity",
      location_name: "Tehran",
      latitude: 35.69,
      longitude: 51.39,
      geo_precision: "point",
      first_seen_at: 12.hours.ago,
      last_seen_at: 1.hour.ago,
      article_count: 8,
      source_count: 5,
      cluster_confidence: 0.84,
      verification_status: "multi_source",
      source_reliability: 0.78,
      geo_confidence: 0.83
    )

    8.times do |i|
      NewsEvent.create!(
        url: "https://example.com/iran-#{i}",
        title: "Iran escalation update #{i}",
        latitude: 35.6,
        longitude: 51.4,
        tone: -5.5,
        category: "conflict",
        credibility: "tier1/low",
        source: ["reuters", "bbc", "cnn", "ap"][i % 4],
        story_cluster_id: iran_cluster.cluster_key,
        published_at: (i + 1).hours.ago,
        fetched_at: Time.current,
      )
    end

    [
      {
        key: "cluster:hormuz-1",
        title: "All eyes on Strait of Hormuz as Iran threatens shipping",
        lat: 38.91,
        lng: -77.04,
        sources: 4,
      },
      {
        key: "cluster:hormuz-2",
        title: "UAE joins allies demanding Iran halt Strait of Hormuz shipping attacks",
        lat: 24.45,
        lng: 54.65,
        sources: 2,
      },
    ].each do |attrs|
      cluster = NewsStoryCluster.create!(
        cluster_key: attrs[:key],
        canonical_title: attrs[:title],
        content_scope: "core",
        event_family: "conflict",
        event_type: "ground_operation",
        location_name: attrs[:title],
        latitude: attrs[:lat],
        longitude: attrs[:lng],
        geo_precision: "point",
        first_seen_at: 30.hours.ago,
        last_seen_at: 2.hours.ago,
        article_count: attrs[:sources],
        source_count: attrs[:sources],
        cluster_confidence: 0.82,
        verification_status: "multi_source",
        source_reliability: 0.77,
        geo_confidence: 0.8
      )
      NewsArticle.create!(
        news_source: source,
        url: "https://example.com/#{attrs[:key]}",
        canonical_url: "https://example.com/#{attrs[:key]}",
        title: attrs[:title],
        normalization_status: "normalized",
        content_scope: "core"
      ).tap do |article|
        cluster.update!(lead_news_article: article)
      end
    end

    data = ConflictPulseService.analyze
    zones = data[:zones] || []
    strategic = data[:strategic_situations] || []

    assert zones.any? { |zone| zone[:situation_name] == "Iran Theater" }
    assert zones.none? { |zone| zone[:situation_name] == "Strait of Hormuz" }

    hormuz = strategic.find { |item| item[:name] == "Strait of Hormuz" }
    assert hormuz.present?, "Expected a promoted strategic Hormuz marker"
    assert_equal "Middle East / Iran War", hormuz[:theater]
    assert_operator hormuz[:direct_cluster_count], :>=, 2
    assert_operator hormuz[:source_count], :>=, 4
    assert_equal "chokepoint", hormuz[:kind]
    assert hormuz[:top_articles].all? { |article| article[:cluster_id].present? }
    refute strategic.any? { |item| ["Strait of Gibraltar", "Bosphorus Strait", "Strait of Malacca"].include?(item[:name]) },
      "Generic corridor words should not promote unrelated chokepoints"
  end

  test "assigns Bosphorus to Russia-Ukraine instead of remote media-capital geocodes" do
    source = NewsSource.create!(canonical_key: "wire-bosphorus", name: "Wire", source_kind: "wire")

    ukraine_cluster = NewsStoryCluster.create!(
      cluster_key: "cluster:ukraine-war",
      canonical_title: "Fighting intensifies in Ukraine",
      content_scope: "core",
      event_family: "conflict",
      event_type: "ground_operation",
      location_name: "Kyiv",
      latitude: 50.45,
      longitude: 30.52,
      geo_precision: "point",
      first_seen_at: 18.hours.ago,
      last_seen_at: 1.hour.ago,
      article_count: 8,
      source_count: 5,
      cluster_confidence: 0.84,
      verification_status: "multi_source",
      source_reliability: 0.79,
      geo_confidence: 0.82
    )

    8.times do |i|
      NewsEvent.create!(
        url: "https://example.com/ukraine-bosphorus-#{i}",
        title: "Ukraine fighting update #{i}",
        latitude: 50.4,
        longitude: 30.5,
        tone: -5.0,
        category: "conflict",
        credibility: "tier1/low",
        source: ["reuters", "bbc", "cnn", "ap"][i % 4],
        story_cluster_id: ukraine_cluster.cluster_key,
        published_at: (i + 1).hours.ago,
        fetched_at: Time.current,
      )
    end

    [
      {
        key: "cluster:bosphorus-1",
        title: "Shipping risk rises in Bosphorus Strait as war pressure grows",
        lat: 38.91,
        lng: -77.04,
        sources: 4,
      },
      {
        key: "cluster:bosphorus-2",
        title: "Bosphorus shipping disruption feared after Black Sea escalation",
        lat: 41.01,
        lng: 28.97,
        sources: 2,
      },
    ].each do |attrs|
      cluster = NewsStoryCluster.create!(
        cluster_key: attrs[:key],
        canonical_title: attrs[:title],
        content_scope: "core",
        event_family: "conflict",
        event_type: "ground_operation",
        location_name: attrs[:title],
        latitude: attrs[:lat],
        longitude: attrs[:lng],
        geo_precision: "point",
        first_seen_at: 30.hours.ago,
        last_seen_at: 2.hours.ago,
        article_count: attrs[:sources],
        source_count: attrs[:sources],
        cluster_confidence: 0.82,
        verification_status: "multi_source",
        source_reliability: 0.77,
        geo_confidence: 0.8
      )
      NewsArticle.create!(
        news_source: source,
        url: "https://example.com/#{attrs[:key]}",
        canonical_url: "https://example.com/#{attrs[:key]}",
        title: attrs[:title],
        normalization_status: "normalized",
        content_scope: "core"
      ).tap do |article|
        cluster.update!(lead_news_article: article)
      end
    end

    data = ConflictPulseService.analyze
    strategic = data[:strategic_situations] || []

    bosphorus = strategic.find { |item| item[:name] == "Bosphorus Strait" }
    assert bosphorus.present?, "Expected Bosphorus strategic marker"
    assert_equal "Russia-Ukraine War", bosphorus[:theater]
    refute_equal "Americas", bosphorus[:theater]
  end
end
