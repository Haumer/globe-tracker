require "test_helper"

class FireClusterServiceTest < ActiveSupport::TestCase
  # detection tuple shape: [latitude, longitude, frp, acq_datetime, satellite]
  def detection(lat, lng, frp, time, satellite = "NOAA-20")
    [lat, lng, frp, time, satellite]
  end

  test "adjacent pixels of one fire collapse into a single cluster" do
    base = Time.utc(2026, 8, 8, 10)
    # Four VIIRS pixels ~375m apart -- one fire, not four.
    detections = [
      detection(47.900, -120.500, 10.0, base),
      detection(47.903, -120.500, 10.0, base),
      detection(47.906, -120.497, 10.0, base),
      detection(47.909, -120.494, 10.0, base),
    ]

    clusters = FireClusterService.build_clusters(detections)

    assert_equal 1, clusters.size
    assert_equal 4, clusters.first[:pixel_count]
  end

  test "a fire straddling a grid cell boundary stays one fire" do
    base = Time.utc(2026, 8, 8, 10)
    # CELL_DEGREES is 0.02, so these land either side of the 47.90 boundary.
    detections = [
      detection(47.8995, -120.5, 20.0, base),
      detection(47.9005, -120.5, 20.0, base),
    ]

    clusters = FireClusterService.build_clusters(detections)

    assert_equal 1, clusters.size, "grid-only grouping would split this into two fires"
  end

  test "genuinely separate fires stay separate" do
    base = Time.utc(2026, 8, 8, 10)
    detections = [
      detection(47.90, -120.50, 15.0, base),
      detection(35.00, 20.00, 15.0, base),
    ]

    assert_equal 2, FireClusterService.build_clusters(detections).size
  end

  # The whole point of the exercise: a fire observed on many passes must not be
  # reported at many times its real output. Production's naive sum inflated the
  # global total 2.6x, and the largest complexes by over 5x.
  test "intensity is the strongest single pass, not the sum across passes" do
    fire = [47.90, -120.50]
    detections = 10.times.map do |i|
      # Same fire, same pixel, ten separate satellite passes an hour apart.
      detection(fire[0], fire[1], 100.0, Time.utc(2026, 8, 8, 0) + i.hours, "NOAA-20")
    end

    cluster = FireClusterService.build_clusters(detections).first

    assert_equal 10, cluster[:pass_count]
    assert_equal 100.0, cluster[:intensity_mw], "must not report 1000 MW for a 100 MW fire"
    assert_equal 1, cluster[:pixel_count], "one pixel seen ten times is still one pixel"
    assert_equal 10, cluster[:detection_count]
  end

  test "pixels within one pass are summed, since they burn simultaneously" do
    base = Time.utc(2026, 8, 8, 10)
    detections = [
      detection(47.900, -120.500, 30.0, base),
      detection(47.903, -120.500, 45.0, base),
      detection(47.906, -120.497, 25.0, base),
    ]

    assert_equal 100.0, FireClusterService.build_clusters(detections).first[:intensity_mw]
  end

  test "two satellites crossing minutes apart count as two passes" do
    at = Time.utc(2026, 8, 8, 10)
    detections = [
      detection(47.90, -120.50, 60.0, at, "NOAA-20"),
      detection(47.90, -120.50, 50.0, at + 4.minutes, "Suomi NPP"),
    ]

    cluster = FireClusterService.build_clusters(detections).first

    assert_equal 2, cluster[:pass_count]
    assert_equal 60.0, cluster[:intensity_mw], "takes the stronger pass, never the sum"
    assert_equal ["NOAA-20", "Suomi NPP"], cluster[:satellites]
  end

  test "latest_mw reports the most recent pass rather than the peak" do
    fire = [47.90, -120.50]
    detections = [
      detection(fire[0], fire[1], 500.0, Time.utc(2026, 8, 8, 2)),
      detection(fire[0], fire[1], 20.0, Time.utc(2026, 8, 8, 9)),
    ]

    cluster = FireClusterService.build_clusters(detections).first

    assert_equal 500.0, cluster[:intensity_mw], "peak stays the peak"
    assert_equal 20.0, cluster[:latest_mw], "a dying fire must be able to show as dying"
  end

  test "tiers follow the megawatt bands" do
    assert_equal "minor", FireCluster.tier_for(9.9)
    assert_equal "moderate", FireCluster.tier_for(10.0)
    assert_equal "major", FireCluster.tier_for(100.0)
    assert_equal "extreme", FireCluster.tier_for(1000.0)
    assert_equal "minor", FireCluster.tier_for(nil)
  end

  test "centre is pulled toward the burning front, not the geometric middle" do
    base = Time.utc(2026, 8, 8, 10)
    detections = [
      detection(47.900, -120.500, 1.0, base),
      detection(47.906, -120.500, 999.0, base),
    ]

    cluster = FireClusterService.build_clusters(detections).first

    assert_in_delta 47.906, cluster[:latitude], 0.001
  end

  test "zero-FRP detections still produce a usable centre" do
    base = Time.utc(2026, 8, 8, 10)
    detections = [
      detection(47.900, -120.500, 0.0, base),
      detection(47.906, -120.500, 0.0, base),
    ]

    cluster = FireClusterService.build_clusters(detections).first

    assert_in_delta 47.903, cluster[:latitude], 0.001
    assert_equal "minor", cluster[:tier]
  end

  test "cluster ids are deterministic for the same footprint" do
    base = Time.utc(2026, 8, 8, 10)
    detections = [detection(47.900, -120.500, 10.0, base), detection(47.903, -120.500, 10.0, base)]

    first = FireClusterService.build_clusters(detections).first[:external_id]
    second = FireClusterService.build_clusters(detections.reverse).first[:external_id]

    assert_equal first, second, "id must not depend on detection ordering"
  end

  test "refresh persists clusters and drops ones that stopped burning" do
    now = Time.utc(2026, 8, 8, 12)
    FireHotspot.delete_all
    FireCluster.delete_all

    FireHotspot.create!(external_id: "a", latitude: 47.90, longitude: -120.50, frp: 250.0,
                        acq_datetime: now - 1.hour, satellite: "NOAA-20", instrument: "VIIRS")

    assert_equal 1, FireClusterService.refresh(now: now)
    cluster = FireCluster.sole
    assert_equal "major", cluster.tier
    assert_in_delta 250.0, cluster.intensity_mw, 0.01

    # The detection ages out of the window; the cluster must not linger.
    assert_equal 0, FireClusterService.refresh(now: now + FireClusterService::WINDOW + 1.hour)
    assert_equal 0, FireCluster.count
  end

  # Regression: 19 columns x one statement hits Postgres's 65,535 bind-parameter
  # ceiling at ~3,400 rows, and a real day produces ~25,000 clusters. A single
  # upsert_all would have failed on the first production run.
  test "persists a realistic number of clusters without exceeding the bind-parameter limit" do
    now = Time.utc(2026, 8, 8, 12)
    FireHotspot.delete_all
    FireCluster.delete_all

    # 5,000 well-separated fires -- above the ~3,400-row failure threshold.
    hotspots = 5_000.times.map do |i|
      { external_id: "h#{i}",
        latitude: -60.0 + (i % 500) * 0.24,
        longitude: -179.0 + (i / 500) * 0.9,
        frp: 50.0, acq_datetime: now - 1.hour,
        satellite: "NOAA-20", instrument: "VIIRS",
        created_at: now, updated_at: now }
    end
    FireHotspot.insert_all(hotspots)

    assert_equal 5_000, FireClusterService.refresh(now: now)
    assert_equal 5_000, FireCluster.count
  end

  test "re-running refresh updates in place rather than duplicating" do
    now = Time.utc(2026, 8, 8, 12)
    FireHotspot.delete_all
    FireCluster.delete_all
    FireHotspot.create!(external_id: "a", latitude: 47.90, longitude: -120.50, frp: 250.0,
                        acq_datetime: now - 1.hour, satellite: "NOAA-20", instrument: "VIIRS")

    FireClusterService.refresh(now: now)
    FireClusterService.refresh(now: now)

    assert_equal 1, FireCluster.count, "stable ids must upsert, not accumulate"
  end

  test "each satellite pass becomes an observation carrying its own source" do
    fire = [47.90, -120.50]
    detections = [
      detection(fire[0], fire[1], 100.0, Time.utc(2026, 8, 8, 2), "NOAA-20"),
      detection(fire[0], fire[1], 400.0, Time.utc(2026, 8, 8, 6), "Suomi NPP"),
      detection(fire[0], fire[1], 250.0, Time.utc(2026, 8, 8, 10), "NOAA-21"),
    ]

    cluster = FireClusterService.build_clusters(detections).first
    series = cluster[:observations].sort_by { |o| o[:acq_datetime] }

    assert_equal 3, series.size
    assert_equal ["NOAA-20", "Suomi NPP", "NOAA-21"], series.map { |o| o[:satellite] }
    assert_equal [100.0, 400.0, 250.0], series.map { |o| o[:frp_mw] }
  end

  test "the observation series reconstructs a fire growing then dying" do
    now = Time.utc(2026, 8, 8, 12)
    FireHotspot.delete_all
    FireCluster.delete_all

    [[Time.utc(2026, 8, 8, 2), 50.0], [Time.utc(2026, 8, 8, 6), 800.0], [Time.utc(2026, 8, 8, 10), 90.0]].each_with_index do |(at, frp), i|
      FireHotspot.create!(external_id: "h#{i}", latitude: 47.90, longitude: -120.50, frp: frp,
                          acq_datetime: at, satellite: "NOAA-2#{i}", instrument: "VIIRS")
    end

    FireClusterService.refresh(now: now)
    cluster = FireCluster.sole

    assert_equal 3, cluster.fire_observations.count
    assert_equal [50.0, 800.0, 90.0], cluster.series.map { |point| point[:mw] }
    assert_equal 800.0, cluster.intensity_mw, "peak is the peak"
    assert_equal 90.0, cluster.latest_mw
    assert_equal "dying", cluster.trend
  end

  # Regression: MODIS resolves 1km pixels and VIIRS 375m, so their radiances are
  # not comparable. Judging the latest MODIS pass against a VIIRS peak labelled
  # the feed's largest fire "dying" while its footprint grew 45 -> 1,424 pixels.
  test "trend never compares a MODIS pass against a VIIRS peak" do
    now = Time.utc(2026, 8, 8, 12)
    FireHotspot.delete_all
    FireCluster.delete_all

    [["Suomi NPP", Time.utc(2026, 8, 8, 4), 50_000.0],
     ["NOAA-20", Time.utc(2026, 8, 8, 8), 44_000.0],
     ["Aqua", Time.utc(2026, 8, 8, 10), 16_000.0]].each_with_index do |(sat, at, frp), i|
      FireHotspot.create!(external_id: "m#{i}", latitude: 47.90, longitude: -120.50, frp: frp,
                          acq_datetime: at, satellite: sat, instrument: sat == "Aqua" ? "MODIS" : "VIIRS")
    end

    cluster = FireClusterService.refresh(now: now) && FireCluster.sole

    assert_equal %w[VIIRS VIIRS MODIS], cluster.fire_observations.chronological.map(&:instrument)
    assert_equal "unknown", cluster.trend,
      "a lone MODIS pass has no same-instrument peak to judge against"
  end

  test "instrument is derived from the platform" do
    base = Time.utc(2026, 8, 8, 10)
    detections = [detection(47.90, -120.50, 10.0, base, "Terra"), detection(10.0, 10.0, 10.0, base, "NOAA-21")]

    instruments = FireClusterService.build_clusters(detections).flat_map { |c| c[:observations].map { |o| o[:instrument] } }

    assert_equal ["MODIS", "VIIRS"], instruments.sort.uniq.sort
  end

  test "trend reads growing when the latest pass is at peak" do
    now = Time.utc(2026, 8, 8, 12)
    FireHotspot.delete_all
    FireCluster.delete_all
    [[Time.utc(2026, 8, 8, 4), 100.0], [Time.utc(2026, 8, 8, 10), 500.0]].each_with_index do |(at, frp), i|
      FireHotspot.create!(external_id: "g#{i}", latitude: 10.0, longitude: 10.0, frp: frp,
                          acq_datetime: at, satellite: "NOAA-20", instrument: "VIIRS")
    end

    FireClusterService.refresh(now: now)
    assert_equal "growing", FireCluster.sole.trend
  end

  test "observations cascade away with their cluster" do
    now = Time.utc(2026, 8, 8, 12)
    FireHotspot.delete_all
    FireCluster.delete_all
    FireHotspot.create!(external_id: "c1", latitude: 47.90, longitude: -120.50, frp: 300.0,
                        acq_datetime: now - 1.hour, satellite: "NOAA-20", instrument: "VIIRS")

    FireClusterService.refresh(now: now)
    assert_equal 1, FireObservation.count

    FireClusterService.refresh(now: now + FireClusterService::WINDOW + 1.hour)
    assert_equal 0, FireCluster.count
    assert_equal 0, FireObservation.count, "observations must not outlive their fire"
  end

  test "one timeline event per fire, not per detection" do
    now = Time.utc(2026, 8, 8, 12)
    FireHotspot.delete_all
    FireCluster.delete_all
    TimelineEvent.where(event_type: "fire").delete_all

    # One fire, twelve detections across four passes.
    12.times do |i|
      FireHotspot.create!(external_id: "t#{i}", latitude: 47.90 + (i % 3) * 0.003, longitude: -120.50,
                          frp: 200.0, acq_datetime: Time.utc(2026, 8, 8, 2) + (i / 3) * 2.hours,
                          satellite: "NOAA-20", instrument: "VIIRS")
    end

    FireClusterService.refresh(now: now)

    events = TimelineEvent.where(event_type: "fire")
    assert_equal 1, events.count, "twelve pixels must not become twelve timeline events"
    assert_equal "FireCluster", events.first.eventable_type
  end

  test "refresh ignores detections outside the window" do
    now = Time.utc(2026, 8, 8, 12)
    FireHotspot.delete_all
    FireCluster.delete_all

    FireHotspot.create!(external_id: "old", latitude: 10.0, longitude: 10.0, frp: 50.0,
                        acq_datetime: now - 3.days, satellite: "Terra", instrument: "MODIS")
    FireHotspot.create!(external_id: "new", latitude: 20.0, longitude: 20.0, frp: 50.0,
                        acq_datetime: now - 1.hour, satellite: "Terra", instrument: "MODIS")

    assert_equal 1, FireClusterService.refresh(now: now)
    assert_in_delta 20.0, FireCluster.sole.latitude, 0.01
  end
end
