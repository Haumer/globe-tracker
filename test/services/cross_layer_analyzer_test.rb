require "test_helper"

class CrossLayerAnalyzerTest < ActiveSupport::TestCase
  # ── earthquake_infrastructure_threats ──────────────────────────

  test "earthquake near nuclear plant returns critical severity" do
    Earthquake.create!(
      external_id: "eq-nuke-1", title: "M6.5 near nuclear plant",
      magnitude: 6.5, latitude: 35.0, longitude: -118.0, depth: 10,
      event_time: 2.hours.ago, fetched_at: Time.current
    )
    PowerPlant.create!(
      gppd_idnr: "PP-NUC-1", name: "Test Nuclear Station",
      latitude: 35.1, longitude: -117.9, primary_fuel: "Nuclear", capacity_mw: 1200
    )

    insights = CrossLayerAnalyzer.analyze
    eq_insights = insights.select { |i| i[:type] == "earthquake_infrastructure" }

    assert_equal 1, eq_insights.size
    assert_equal "critical", eq_insights.first[:severity]
    assert_includes eq_insights.first[:title], "NUCLEAR"
  end

  test "earthquake near submarine cables returns high severity" do
    Earthquake.create!(
      external_id: "eq-cable-1", title: "M5.8 undersea quake",
      magnitude: 5.8, latitude: 10.0, longitude: -60.0, depth: 15,
      event_time: 6.hours.ago, fetched_at: Time.current
    )
    SubmarineCable.create!(
      cable_id: "cable-1", name: "Transatlantic Express",
      coordinates: [[-60.0, 10.0], [-59.5, 10.2], [-59.0, 10.5]]
    )
    SubmarineCable.create!(
      cable_id: "cable-2", name: "Caribbean Link",
      coordinates: [[-60.1, 9.9], [-59.8, 10.1]]
    )

    insights = CrossLayerAnalyzer.analyze
    eq_insights = insights.select { |i| i[:type] == "earthquake_infrastructure" }

    assert_equal 1, eq_insights.size
    assert_equal "high", eq_insights.first[:severity]
    assert_includes eq_insights.first[:title], "submarine cable"
  end

  test "small earthquake with no nearby infrastructure produces no insight" do
    Earthquake.create!(
      external_id: "eq-remote-1", title: "M4.8 middle of ocean",
      magnitude: 4.8, latitude: -40.0, longitude: 170.0, depth: 30,
      event_time: 3.hours.ago, fetched_at: Time.current
    )

    insights = CrossLayerAnalyzer.analyze
    eq_insights = insights.select { |i| i[:type] == "earthquake_infrastructure" }
    assert_empty eq_insights
  end

  test "earthquake infrastructure insight includes corroborating multi-source news cluster" do
    quake_time = 3.hours.ago

    Earthquake.create!(
      external_id: "eq-news-1", title: "M6.1 near major city",
      magnitude: 6.1, latitude: 37.0, longitude: 38.0, depth: 12,
      event_time: quake_time, fetched_at: Time.current
    )
    PowerPlant.create!(
      gppd_idnr: "PP-NEWS-1", name: "Regional Grid Plant",
      latitude: 37.1, longitude: 38.1, primary_fuel: "Gas", capacity_mw: 700
    )
    NewsStoryCluster.create!(
      cluster_key: "news-eq-1",
      canonical_title: "Strong earthquake reported near Gaziantep",
      content_scope: "adjacent",
      event_family: "disaster",
      event_type: "earthquake",
      location_name: "Gaziantep",
      latitude: 37.05,
      longitude: 38.02,
      geo_precision: "city",
      first_seen_at: quake_time + 1.hour,
      last_seen_at: quake_time + 2.hours,
      article_count: 4,
      source_count: 3,
      verification_status: "multi_source"
    )

    insights = CrossLayerAnalyzer.analyze
    eq_insight = insights.find { |i| i[:type] == "earthquake_infrastructure" }

    assert eq_insight
    assert_includes eq_insight[:title], "Reported"
    assert_equal "news-eq-1", eq_insight[:entities][:news].first[:cluster_key]
    assert_includes eq_insight[:description], "corroborated by 1 news cluster"
  end

  test "single-source earthquake news cluster is not attached to earthquake infrastructure insight" do
    quake_time = 2.hours.ago

    Earthquake.create!(
      external_id: "eq-news-2", title: "M5.4 event near coast",
      magnitude: 5.4, latitude: 42.0, longitude: 27.0, depth: 18,
      event_time: quake_time, fetched_at: Time.current
    )
    PowerPlant.create!(
      gppd_idnr: "PP-NEWS-2", name: "Coastal Plant",
      latitude: 42.1, longitude: 27.1, primary_fuel: "Coal", capacity_mw: 500
    )
    NewsStoryCluster.create!(
      cluster_key: "news-eq-single",
      canonical_title: "Unconfirmed quake reports",
      content_scope: "adjacent",
      event_family: "disaster",
      event_type: "earthquake",
      location_name: "Black Sea coast",
      latitude: 42.0,
      longitude: 27.0,
      geo_precision: "region",
      first_seen_at: quake_time + 30.minutes,
      last_seen_at: quake_time + 1.hour,
      article_count: 1,
      source_count: 1,
      verification_status: "single_source"
    )

    insights = CrossLayerAnalyzer.analyze
    eq_insight = insights.find { |i| i[:type] == "earthquake_infrastructure" }

    assert eq_insight
    assert_empty eq_insight[:entities][:news]
    refute_includes eq_insight[:title], "Reported"
  end

  test "earthquake below 4.5 magnitude is excluded" do
    Earthquake.create!(
      external_id: "eq-small-1", title: "M4.2 minor",
      magnitude: 4.2, latitude: 35.0, longitude: -118.0, depth: 10,
      event_time: 1.hour.ago, fetched_at: Time.current
    )
    PowerPlant.create!(
      gppd_idnr: "PP-COAL-1", name: "Nearby Coal Plant",
      latitude: 35.05, longitude: -117.95, primary_fuel: "Coal", capacity_mw: 500
    )

    insights = CrossLayerAnalyzer.analyze
    eq_insights = insights.select { |i| i[:type] == "earthquake_infrastructure" }
    assert_empty eq_insights
  end

  # ── jamming_flight_impacts ────────────────────────────────────

  test "GPS jamming zone with civilian flights returns jamming_flights insight" do
    GpsJammingSnapshot.create!(
      cell_lat: 50.0, cell_lng: 35.0, total: 100, bad: 35,
      percentage: 35.0, level: "severe", recorded_at: 30.minutes.ago
    )
    5.times do |i|
      Flight.create!(
        icao24: "jam-civ-#{i}", callsign: "CIV#{i}",
        latitude: 50.2 + i * 0.01, longitude: 35.1, altitude: 35000,
        origin_country: "Ukraine", military: false
      )
    end

    insights = CrossLayerAnalyzer.analyze
    jam_insights = insights.select { |i| i[:type] == "jamming_flights" }

    assert_equal 1, jam_insights.size
    assert_equal "high", jam_insights.first[:severity]  # percentage > 30
    assert_includes jam_insights.first[:title], "civilian"
  end

  test "GPS jamming with 3+ military flights returns electronic_warfare" do
    GpsJammingSnapshot.create!(
      cell_lat: 50.0, cell_lng: 35.0, total: 100, bad: 20,
      percentage: 20.0, level: "moderate", recorded_at: 20.minutes.ago
    )
    5.times do |i|
      Flight.create!(
        icao24: "ew-mil-#{i}", callsign: "MIL#{i}",
        latitude: 50.1 + i * 0.01, longitude: 35.1, altitude: 25000,
        origin_country: "US", military: true
      )
    end

    insights = CrossLayerAnalyzer.analyze
    ew_insights = insights.select { |i| i[:type] == "electronic_warfare" }

    assert_equal 1, ew_insights.size
    assert_includes ew_insights.first[:title], "electronic warfare"
  end

  test "GPS jamming with no flights produces no insight" do
    GpsJammingSnapshot.create!(
      cell_lat: -60.0, cell_lng: -60.0, total: 50, bad: 25,
      percentage: 50.0, level: "severe", recorded_at: 15.minutes.ago
    )

    insights = CrossLayerAnalyzer.analyze
    jam_insights = insights.select { |i| i[:type] == "jamming_flights" }
    assert_empty jam_insights
  end

  # ── conflict_military_surge ───────────────────────────────────

  test "conflict zone with multi-national military flights returns insight" do
    6.times do |i|
      ConflictEvent.create!(
        external_id: 9000 + i, conflict_name: "Test Conflict",
        latitude: 15.0 + i * 0.1, longitude: 45.0 + i * 0.1,
        date_start: (1 + i).days.ago, country: "Yemen",
        type_of_violence: 1
      )
    end
    3.times do |i|
      Flight.create!(
        icao24: "conf-mil-us-#{i}", callsign: "REAPER#{i}",
        latitude: 15.2, longitude: 45.2, altitude: 20000,
        origin_country: "United States", military: true
      )
    end
    3.times do |i|
      Flight.create!(
        icao24: "conf-mil-uk-#{i}", callsign: "HAWK#{i}",
        latitude: 15.3, longitude: 45.3, altitude: 22000,
        origin_country: "United Kingdom", military: true
      )
    end

    insights = CrossLayerAnalyzer.analyze
    conflict_insights = insights.select { |i| i[:type] == "conflict_military" }

    assert_equal 1, conflict_insights.size
    assert_includes conflict_insights.first[:title], "Test Conflict"
    assert_equal 6, conflict_insights.first[:entities][:flights][:military]
  end

  test "conflict zone with fewer than 5 military flights produces no insight" do
    6.times do |i|
      ConflictEvent.create!(
        external_id: 8000 + i, conflict_name: "Small Conflict",
        latitude: 30.0, longitude: 50.0, date_start: (1 + i).days.ago,
        country: "Iraq", type_of_violence: 2
      )
    end
    4.times do |i|
      Flight.create!(
        icao24: "small-mil-#{i}", callsign: "JET#{i}",
        latitude: 30.0, longitude: 50.0, altitude: 30000,
        origin_country: "US", military: true
      )
    end

    insights = CrossLayerAnalyzer.analyze
    conflict_insights = insights.select { |i| i[:type] == "conflict_military" }
    assert_empty conflict_insights
  end

  test "conflict with fewer than 5 events is excluded" do
    3.times do |i|
      ConflictEvent.create!(
        external_id: 7000 + i, conflict_name: "Minor Skirmish",
        latitude: 20.0, longitude: 40.0, date_start: 3.days.ago,
        country: "Somalia", type_of_violence: 1
      )
    end
    6.times do |i|
      Flight.create!(
        icao24: "minor-mil-#{i}", callsign: "HAWK#{i}",
        latitude: 20.0, longitude: 40.0, altitude: 25000,
        origin_country: "US", military: true
      )
    end

    insights = CrossLayerAnalyzer.analyze
    conflict_insights = insights.select { |i| i[:type] == "conflict_military" }
    assert_empty conflict_insights
  end

  # ── fire_infrastructure_threats ───────────────────────────────

  test "fire cluster near nuclear plant returns critical" do
    6.times do |i|
      FireHotspot.create!(
        external_id: "fire-nuke-#{i}", latitude: 44.0 + i * 0.01,
        longitude: -80.0, brightness: 350, confidence: "high",
        frp: 50.0 + i * 10, acq_datetime: 4.hours.ago
      )
    end
    PowerPlant.create!(
      gppd_idnr: "PP-NUC-FIRE", name: "Nearby Nuclear Plant",
      latitude: 44.0, longitude: -80.0, primary_fuel: "Nuclear", capacity_mw: 900
    )

    insights = CrossLayerAnalyzer.analyze
    fire_insights = insights.select { |i| i[:type] == "fire_infrastructure" }

    assert_equal 1, fire_insights.size
    assert_equal "critical", fire_insights.first[:severity]
    assert_includes fire_insights.first[:description], "NUCLEAR"
  end

  test "large fire cluster near coal plant returns high severity" do
    25.times do |i|
      FireHotspot.create!(
        external_id: "fire-coal-#{i}", latitude: 38.0 + (i % 5) * 0.01,
        longitude: -95.0 + (i / 5) * 0.01, brightness: 300,
        confidence: "nominal", frp: 40.0, acq_datetime: 6.hours.ago
      )
    end
    PowerPlant.create!(
      gppd_idnr: "PP-COAL-FIRE", name: "Prairie Coal Plant",
      latitude: 38.0, longitude: -95.0, primary_fuel: "Coal", capacity_mw: 600
    )

    insights = CrossLayerAnalyzer.analyze
    fire_insights = insights.select { |i| i[:type] == "fire_infrastructure" }

    assert_equal 1, fire_insights.size
    assert_equal "high", fire_insights.first[:severity]
  end

  test "fire cluster with no nearby plants produces no insight" do
    6.times do |i|
      FireHotspot.create!(
        external_id: "fire-remote-#{i}", latitude: -30.0,
        longitude: 25.0, brightness: 400, confidence: "h",
        frp: 80.0, acq_datetime: 2.hours.ago
      )
    end

    insights = CrossLayerAnalyzer.analyze
    fire_insights = insights.select { |i| i[:type] == "fire_infrastructure" }
    assert_empty fire_insights
  end

  test "fewer than 5 fires in cluster is excluded" do
    4.times do |i|
      FireHotspot.create!(
        external_id: "fire-few-#{i}", latitude: 44.0,
        longitude: -80.0, brightness: 350, confidence: "high",
        frp: 50.0, acq_datetime: 3.hours.ago
      )
    end
    PowerPlant.create!(
      gppd_idnr: "PP-FEW-FIRE", name: "Safe Plant",
      latitude: 44.0, longitude: -80.0, primary_fuel: "Gas", capacity_mw: 300
    )

    insights = CrossLayerAnalyzer.analyze
    fire_insights = insights.select { |i| i[:type] == "fire_infrastructure" }
    assert_empty fire_insights
  end

  # ── cable_outage_correlations ─────────────────────────────────

  test "internet outage with recent earthquake returns cable_outage insight" do
    Earthquake.create!(
      external_id: "eq-outage-1", title: "M5.5 undersea",
      magnitude: 5.5, latitude: 36.0, longitude: 140.0, depth: 20,
      event_time: 12.hours.ago, fetched_at: Time.current
    )
    InternetOutage.create!(
      external_id: "outage-1", entity_type: "country", entity_code: "JP",
      entity_name: "Japan", level: "critical", score: 85.0,
      started_at: 6.hours.ago
    )

    insights = CrossLayerAnalyzer.analyze
    cable_insights = insights.select { |i| i[:type] == "cable_outage" }

    assert_equal 1, cable_insights.size
    assert_equal "high", cable_insights.first[:severity]
    assert_includes cable_insights.first[:title], "Japan"
  end

  test "cable outage insight includes traffic degradation and corroborating outage news" do
    quake_time = 10.hours.ago
    outage_time = 4.hours.ago

    Earthquake.create!(
      external_id: "eq-outage-news", title: "M6.0 offshore quake",
      magnitude: 6.0, latitude: 36.0, longitude: 140.0, depth: 25,
      event_time: quake_time, fetched_at: Time.current
    )
    InternetOutage.create!(
      external_id: "outage-jp-news", entity_type: "country", entity_code: "JP",
      entity_name: "Japan", level: "critical", score: 88.0,
      started_at: outage_time
    )
    InternetTrafficSnapshot.create!(
      country_code: "JP", country_name: "Japan", traffic_pct: 61.5,
      attack_origin_pct: 0.2, attack_target_pct: 1.4, recorded_at: 30.minutes.ago
    )
    NewsStoryCluster.create!(
      cluster_key: "jp-outage-cluster",
      canonical_title: "Japan outage reported after offshore quake",
      content_scope: "adjacent",
      event_family: "infrastructure",
      event_type: "outage",
      location_name: "Japan",
      latitude: 36.0,
      longitude: 138.0,
      geo_precision: "country",
      first_seen_at: outage_time + 30.minutes,
      last_seen_at: outage_time + 2.hours,
      article_count: 5,
      source_count: 3,
      verification_status: "multi_source"
    )

    insights = CrossLayerAnalyzer.analyze
    cable_insight = insights.find { |i| i[:type] == "cable_outage" }

    assert cable_insight
    assert_equal "JP", cable_insight[:entities][:traffic][:country_code]
    assert_equal "jp-outage-cluster", cable_insight[:entities][:news].first[:cluster_key]
    assert_includes cable_insight[:description], "traffic at 61.5% of baseline"
  end

  test "internet outage without recent earthquake produces no insight" do
    InternetOutage.create!(
      external_id: "outage-lonely", entity_type: "country", entity_code: "DE",
      entity_name: "Germany", level: "major", score: 70.0,
      started_at: 3.hours.ago
    )

    insights = CrossLayerAnalyzer.analyze
    cable_insights = insights.select { |i| i[:type] == "cable_outage" }
    assert_empty cable_insights
  end

  test "outage with non-country entity_type is excluded from cable correlation" do
    Earthquake.create!(
      external_id: "eq-asn-1", title: "M5.2 quake",
      magnitude: 5.2, latitude: 40.0, longitude: -74.0, depth: 15,
      event_time: 6.hours.ago, fetched_at: Time.current
    )
    InternetOutage.create!(
      external_id: "outage-asn", entity_type: "asn", entity_code: "AS1234",
      entity_name: "Example ISP", level: "critical", score: 90.0,
      started_at: 2.hours.ago
    )

    insights = CrossLayerAnalyzer.analyze
    cable_insights = insights.select { |i| i[:type] == "cable_outage" }
    assert_empty cable_insights
  end

  # ── analyze integration ───────────────────────────────────────

  test "analyze returns insights sorted by severity descending" do
    # Critical: nuclear + earthquake
    Earthquake.create!(
      external_id: "eq-sort-1", title: "M7.0 big one",
      magnitude: 7.0, latitude: 35.0, longitude: -118.0, depth: 10,
      event_time: 1.hour.ago, fetched_at: Time.current
    )
    PowerPlant.create!(
      gppd_idnr: "PP-SORT-NUC", name: "Sort Nuclear",
      latitude: 35.1, longitude: -117.9, primary_fuel: "Nuclear", capacity_mw: 1000
    )

    # Medium: GPS jamming with civilian flights only, low percentage
    GpsJammingSnapshot.create!(
      cell_lat: -20.0, cell_lng: 30.0, total: 100, bad: 12,
      percentage: 12.0, level: "low", recorded_at: 20.minutes.ago
    )
    3.times do |i|
      Flight.create!(
        icao24: "sort-civ-#{i}", callsign: "SORT#{i}",
        latitude: -19.9, longitude: 30.1, altitude: 35000,
        origin_country: "ZA", military: false
      )
    end

    insights = CrossLayerAnalyzer.analyze
    assert insights.size >= 2
    severities = insights.map { |i| i[:severity] }
    score_map = { "critical" => 4, "high" => 3, "medium" => 2, "low" => 1 }
    scores = severities.map { |s| score_map[s] }
    assert_equal scores, scores.sort.reverse, "Insights should be sorted by severity descending"
  end

  test "analyze with no data returns empty array" do
    assert_equal [], CrossLayerAnalyzer.analyze
  end

  # ── emergency_squawk_correlations ──────────────────────────

  test "hijack squawk returns critical" do
    Flight.create!(
      icao24: "squawk-7500", callsign: "HIJACK1",
      latitude: 40.0, longitude: -74.0, altitude: 30000,
      origin_country: "US", military: false, squawk: "7500"
    )

    insights = CrossLayerAnalyzer.analyze
    sq_insights = insights.select { |i| i[:type] == "emergency_squawk" }

    assert_equal 1, sq_insights.size
    assert_equal "critical", sq_insights.first[:severity]
    assert_includes sq_insights.first[:title], "HIJACK"
  end

  test "NORDO squawk near jamming returns critical" do
    Flight.create!(
      icao24: "squawk-7600", callsign: "NORDO1",
      latitude: 50.0, longitude: 35.0, altitude: 35000,
      origin_country: "Germany", military: false, squawk: "7600"
    )
    GpsJammingSnapshot.create!(
      cell_lat: 50.0, cell_lng: 35.0, total: 50, bad: 10,
      percentage: 20.0, level: "moderate", recorded_at: 30.minutes.ago
    )

    insights = CrossLayerAnalyzer.analyze
    sq_insights = insights.select { |i| i[:type] == "emergency_squawk" }

    assert sq_insights.any?
    nordo = sq_insights.find { |i| i[:title].include?("NORDO") }
    assert_equal "critical", nordo[:severity]
    assert_includes nordo[:title], "GPS jamming"
  end

  test "emergency squawk without context returns medium" do
    Flight.create!(
      icao24: "squawk-7700", callsign: "EMG1",
      latitude: -30.0, longitude: 25.0, altitude: 20000,
      origin_country: "South Africa", military: false, squawk: "7700"
    )

    insights = CrossLayerAnalyzer.analyze
    sq_insights = insights.select { |i| i[:type] == "emergency_squawk" }

    assert_equal 1, sq_insights.size
    assert_equal "medium", sq_insights.first[:severity]
  end

  # ── electronic_warfare (merged into jamming_flights) ───────

  test "jamming with 3+ military flights produces electronic_warfare" do
    GpsJammingSnapshot.create!(
      cell_lat: 55.0, cell_lng: 25.0, total: 80, bad: 20,
      percentage: 25.0, level: "moderate", recorded_at: 20.minutes.ago
    )
    4.times do |i|
      Flight.create!(
        icao24: "ew-test-#{i}", callsign: "EAGLE#{i}",
        latitude: 55.1, longitude: 25.1, altitude: 30000,
        origin_country: "US", military: true
      )
    end

    insights = CrossLayerAnalyzer.analyze
    ew = insights.select { |i| i[:type] == "electronic_warfare" }

    assert_equal 1, ew.size
    assert_includes ew.first[:title], "electronic warfare"
  end

  test "jamming with 2 military flights produces jamming_flights not EW" do
    GpsJammingSnapshot.create!(
      cell_lat: 55.0, cell_lng: 25.0, total: 80, bad: 20,
      percentage: 25.0, level: "moderate", recorded_at: 20.minutes.ago
    )
    2.times do |i|
      Flight.create!(
        icao24: "ew-few-#{i}", callsign: "JET#{i}",
        latitude: 55.1, longitude: 25.1, altitude: 30000,
        origin_country: "US", military: true
      )
    end
    5.times do |i|
      Flight.create!(
        icao24: "ew-civ-#{i}", callsign: "CIV#{i}",
        latitude: 55.2, longitude: 25.2, altitude: 35000,
        origin_country: "Germany", military: false
      )
    end

    insights = CrossLayerAnalyzer.analyze
    jam = insights.select { |i| i[:type] == "jamming_flights" }
    ew = insights.select { |i| i[:type] == "electronic_warfare" }

    assert_equal 1, jam.size
    assert_empty ew
  end

  # ── information_blackout ───────────────────────────────────

  test "internet outage during conflict returns information_blackout" do
    InternetOutage.create!(
      external_id: "blackout-1", entity_type: "country", entity_code: "SD",
      entity_name: "Sudan", level: "critical", score: 90.0,
      started_at: 3.hours.ago
    )
    InternetOutage.create!(
      external_id: "blackout-2", entity_type: "country", entity_code: "SD",
      entity_name: "Sudan", level: "major", score: 80.0,
      started_at: 2.hours.ago
    )
    InternetOutage.create!(
      external_id: "blackout-3", entity_type: "country", entity_code: "SD",
      entity_name: "Sudan", level: "critical", score: 85.0,
      started_at: 1.hour.ago
    )
    3.times do |i|
      ConflictEvent.create!(
        external_id: 6000 + i, conflict_name: "Sudan Crisis",
        latitude: 16.0, longitude: 30.0, date_start: (1 + i).days.ago,
        country: "Sudan", type_of_violence: 1
      )
    end

    insights = CrossLayerAnalyzer.analyze
    blackout = insights.select { |i| i[:type] == "information_blackout" }

    assert_equal 1, blackout.size
    assert_equal "critical", blackout.first[:severity]
    assert_includes blackout.first[:title], "Sudan"
  end

  test "information blackout insight includes traffic degradation and corroborating news" do
    outage_time = 3.hours.ago

    2.times do |i|
      InternetOutage.create!(
        external_id: "blackout-news-#{i}", entity_type: "country", entity_code: "SD",
        entity_name: "Sudan", level: "critical", score: 88.0 - i,
        started_at: outage_time + i.minutes
      )
    end
    InternetTrafficSnapshot.create!(
      country_code: "SD", country_name: "Sudan", traffic_pct: 42.0,
      attack_origin_pct: 0.0, attack_target_pct: 0.3, recorded_at: 20.minutes.ago
    )
    3.times do |i|
      ConflictEvent.create!(
        external_id: 7100 + i, conflict_name: "Khartoum Fighting",
        latitude: 15.6, longitude: 32.5, date_start: (i + 1).days.ago,
        country: "Sudan", type_of_violence: 1
      )
    end
    NewsStoryCluster.create!(
      cluster_key: "sudan-blackout-cluster",
      canonical_title: "Sudan communications blackout reported during fighting",
      content_scope: "adjacent",
      event_family: "infrastructure",
      event_type: "outage",
      location_name: "Sudan",
      latitude: 16.0,
      longitude: 30.0,
      geo_precision: "country",
      first_seen_at: outage_time + 45.minutes,
      last_seen_at: outage_time + 90.minutes,
      article_count: 6,
      source_count: 4,
      verification_status: "multi_source"
    )

    insights = CrossLayerAnalyzer.analyze
    blackout = insights.find { |i| i[:type] == "information_blackout" }

    assert blackout
    assert_equal "SD", blackout[:entities][:traffic][:country_code]
    assert_equal "sudan-blackout-cluster", blackout[:entities][:news].first[:cluster_key]
    assert_includes blackout[:description], "traffic at 42.0% of baseline"
  end

  # ── weather_disruption ──────────────────────────────────────

  test "severe weather with flights returns weather_disruption" do
    WeatherAlert.create!(
      external_id: "wx-1", event: "Tornado Warning", severity: "Extreme",
      latitude: 35.0, longitude: -97.0, onset: 1.hour.ago,
      expires: 2.hours.from_now, fetched_at: Time.current
    )
    15.times do |i|
      Flight.create!(
        icao24: "wx-flt-#{i}", callsign: "WX#{i}",
        latitude: 35.0 + i * 0.05, longitude: -97.0, altitude: 35000,
        origin_country: "US", military: false
      )
    end

    insights = CrossLayerAnalyzer.analyze
    wx = insights.select { |i| i[:type] == "weather_disruption" }

    assert_equal 1, wx.size
    assert_equal "high", wx.first[:severity] # Extreme = high
    assert_includes wx.first[:title], "Tornado Warning"
  end

  test "weather disruption includes nearby camera feeds" do
    WeatherAlert.create!(
      external_id: "wx-cam-1", event: "Severe Thunderstorm", severity: "Severe",
      latitude: 47.8, longitude: 18.99, onset: 1.hour.ago,
      expires: 2.hours.from_now, fetched_at: Time.current
    )
    12.times do |i|
      Flight.create!(
        icao24: "wx-cam-flt-#{i}", callsign: "CAM#{i}",
        latitude: 47.75 + i * 0.01, longitude: 19.0, altitude: 31000,
        origin_country: "Hungary", military: false
      )
    end
    Camera.create!(
      webcam_id: "cam-wx-1", source: "windy", title: "Visegrad Ridge Cam",
      latitude: 47.799, longitude: 18.991, status: "active",
      city: "Visegrad", country: "Hungary", expires_at: 1.day.from_now
    )

    insights = CrossLayerAnalyzer.analyze
    wx = insights.find { |i| i[:type] == "weather_disruption" }

    assert wx
    assert_equal "Visegrad Ridge Cam", wx[:entities][:cameras].first[:title]
    assert_includes wx[:description], "nearby camera feed"
  end

  test "severe weather with fewer than 10 flights produces no insight" do
    WeatherAlert.create!(
      external_id: "wx-quiet", event: "Severe Thunderstorm", severity: "Severe",
      latitude: -40.0, longitude: 170.0, onset: 1.hour.ago,
      expires: 3.hours.from_now, fetched_at: Time.current
    )
    3.times do |i|
      Flight.create!(
        icao24: "wx-few-#{i}", callsign: "FEW#{i}",
        latitude: -40.0, longitude: 170.0, altitude: 30000,
        origin_country: "NZ", military: false
      )
    end

    insights = CrossLayerAnalyzer.analyze
    wx = insights.select { |i| i[:type] == "weather_disruption" }
    assert_empty wx
  end

  # ── ship_cable_proximity ────────────────────────────────────

  test "stopped ship near cable returns insight" do
    Ship.create!(
      mmsi: "123456789", name: "Suspicious Vessel",
      latitude: 10.0, longitude: -60.0, speed: 0.2, heading: 180,
      flag: "RU"
    )
    SubmarineCable.create!(
      cable_id: "cable-ship-1", name: "Atlantic Cable",
      coordinates: [[-60.0, 10.0], [-59.5, 10.2]]
    )

    insights = CrossLayerAnalyzer.analyze
    ship = insights.select { |i| i[:type] == "ship_cable_proximity" }

    assert_equal 1, ship.size
    assert_includes ship.first[:title], "Suspicious Vessel"
    assert_includes ship.first[:title], "Atlantic Cable"
  end

  test "moving ship near cable produces no insight" do
    Ship.create!(
      mmsi: "987654321", name: "Normal Cargo",
      latitude: 10.0, longitude: -60.0, speed: 12.0, heading: 90,
      flag: "PA"
    )
    SubmarineCable.create!(
      cable_id: "cable-ship-2", name: "Pacific Cable",
      coordinates: [[-60.0, 10.0], [-59.5, 10.2]]
    )

    insights = CrossLayerAnalyzer.analyze
    ship = insights.select { |i| i[:type] == "ship_cable_proximity" }
    assert_empty ship
  end

  test "chokepoint disruption normalizes corrupted chokepoint names" do
    corrupted_name = "Suez Canal carries 12% of global oil, making Brent Crude a direct flow dependency benchmark (latest 0.0%)"
    mocked_payload = [{
      id: "suez",
      name: corrupted_name,
      lat: 30.46,
      lng: 32.34,
      status: "elevated",
      ships_nearby: { total: 0, tankers: 0, cargo: 0 },
      flows: { oil: { pct: 12, note: "Europe-bound crude & refined products" } },
      commodity_signals: [],
      conflict_pulse: [{ score: 61, trend: "escalating" }],
      checked_at: Time.current.iso8601,
    }]

    original_analyze = ChokepointMonitorService.method(:analyze)
    ChokepointMonitorService.singleton_class.send(:define_method, :analyze) { mocked_payload }

    begin
      insight = CrossLayerAnalyzer.analyze.find { |row| row[:type] == "chokepoint_disruption" }

      assert insight
      assert_equal "Suez Canal: escalating conflict near 12% of world oil", insight[:title]
      assert_equal "Suez Canal", insight.dig(:entities, :chokepoint, :name)
    ensure
      ChokepointMonitorService.singleton_class.send(:define_method, :analyze, original_analyze)
    end
  end

  test "chokepoint market stress fires when commodity signals move materially" do
    mocked_payload = [{
      id: "bab_el_mandeb",
      name: "Bab el-Mandeb",
      lat: 12.58,
      lng: 43.33,
      status: "elevated",
      ships_nearby: { total: 18, tankers: 6, cargo: 7 },
      flows: { oil: { pct: 9, note: "Europe-bound energy flows" } },
      commodity_signals: [
        { symbol: "OIL_BRENT", name: "Brent Crude", price: 87.4, change_pct: 2.8 },
        { symbol: "LNG", name: "LNG (Asia)", price: 13.1, change_pct: 1.2 },
      ],
      conflict_pulse: [{ score: 64, trend: "escalating" }],
      checked_at: Time.current.iso8601,
    }]

    original_analyze = ChokepointMonitorService.method(:analyze)
    ChokepointMonitorService.singleton_class.send(:define_method, :analyze) { mocked_payload }

    begin
      insight = CrossLayerAnalyzer.analyze.find { |row| row[:type] == "chokepoint_market_stress" }

      assert insight
      assert_equal "high", insight[:severity]
      assert_includes insight[:title], "OIL_BRENT"
      assert_equal "Bab el-Mandeb", insight.dig(:entities, :chokepoint, :name)
    ensure
      ChokepointMonitorService.singleton_class.send(:define_method, :analyze, original_analyze)
    end
  end

  test "outage currency stress fires when a country outage coincides with an FX move" do
    CommodityPrice.create!(
      symbol: "JPY",
      category: "currency",
      name: "Japanese Yen (USD/JPY)",
      price: 0.0068,
      change_pct: -0.92,
      unit: "USD/JPY",
      latitude: 35.68,
      longitude: 139.69,
      region: "Japan",
      recorded_at: Time.current,
    )
    InternetOutage.create!(
      external_id: "jp-fx-outage",
      entity_type: "country",
      entity_code: "JP",
      entity_name: "Japan",
      level: "critical",
      score: 86.0,
      started_at: 2.hours.ago,
    )
    InternetTrafficSnapshot.create!(
      country_code: "JP",
      country_name: "Japan",
      traffic_pct: 58.4,
      attack_origin_pct: 0.0,
      attack_target_pct: 0.4,
      recorded_at: 20.minutes.ago,
    )

    insight = CrossLayerAnalyzer.analyze.find { |row| row[:type] == "outage_currency_stress" }

    assert insight
    assert_equal "high", insight[:severity]
    assert_includes insight[:title], "JPY"
    assert_equal "JP", insight.dig(:entities, :traffic, :country_code)
  end
end
