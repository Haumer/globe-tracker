require "test_helper"

class PurgeStaleDataJobTest < ActiveSupport::TestCase
  # Comfortably inside / outside the 14-day window without sitting on the edge.
  FRESH = 2.days
  STALE = 20.days

  test "is assigned to the background queue" do
    assert_equal "background", PurgeStaleDataJob.new.queue_name
  end

  test "runs without error" do
    assert_nothing_raised { PurgeStaleDataJob.perform_now }
  end

  test "keeps observations inside the window and drops those outside it" do
    retained = position_snapshot("retained", FRESH.ago)
    stale = position_snapshot("stale", STALE.ago)
    fresh_fire = FireHotspot.create!(external_id: "fire-fresh", latitude: 1, longitude: 1, acq_datetime: FRESH.ago)
    stale_fire = FireHotspot.create!(external_id: "fire-stale", latitude: 2, longitude: 2, acq_datetime: STALE.ago)

    PurgeStaleDataJob.perform_now

    assert PositionSnapshot.exists?(retained.id)
    assert_not PositionSnapshot.exists?(stale.id)
    assert FireHotspot.exists?(fresh_fire.id)
    assert_not FireHotspot.exists?(stale_fire.id)
  end

  # The regression this ordering exists for: a claim can carry a newer
  # published_at than the article it hangs off. Purging by each row's own
  # timestamp would delete the article and leave the claim behind, tripping
  # the foreign key. Children must go by reference to their stale parent.
  test "cascades the news graph even when a child is newer than its article" do
    source = NewsSource.create!(canonical_key: "purge-src", name: "BBC", source_kind: "publisher")
    ingest = NewsIngest.create!(
      source_feed: "purge-feed", source_endpoint_url: "https://example.com/feed",
      fetched_at: STALE.ago, payload_format: "rss", content_hash: "purge-hash-1"
    )
    article = NewsArticle.create!(
      news_source: source, news_ingest: ingest,
      url: "https://bbc.com/purge-1", canonical_url: "https://bbc.com/purge-1",
      normalization_status: "normalized", content_scope: "core", published_at: STALE.ago
    )
    claim = NewsClaim.create!(
      news_article: article, event_type: "diplomacy", event_family: "political",
      extraction_method: "heuristic", extraction_version: "v1",
      verification_status: "unverified", geo_precision: "unknown",
      published_at: FRESH.ago
    )
    actor = NewsActor.create!(canonical_key: "purge-actor", name: "NATO", actor_type: "org")
    claim_actor = NewsClaimActor.create!(news_claim: claim, news_actor: actor, role: "subject", position: 1)

    assert_nothing_raised { PurgeStaleDataJob.perform_now }

    assert_not NewsClaimActor.exists?(claim_actor.id), "claim actor should follow its claim"
    assert_not NewsClaim.exists?(claim.id), "claim should follow its article despite a fresher timestamp"
    assert_not NewsArticle.exists?(article.id)
    assert_not NewsIngest.exists?(ingest.id), "ingest should go once nothing references it"
  end

  test "keeps a stale ingest that a fresh article still points at" do
    source = NewsSource.create!(canonical_key: "purge-src-2", name: "CNN", source_kind: "publisher")
    ingest = NewsIngest.create!(
      source_feed: "purge-feed-2", source_endpoint_url: "https://example.com/feed2",
      fetched_at: STALE.ago, payload_format: "rss", content_hash: "purge-hash-2"
    )
    fresh_article = NewsArticle.create!(
      news_source: source, news_ingest: ingest,
      url: "https://cnn.com/purge-2", canonical_url: "https://cnn.com/purge-2",
      normalization_status: "normalized", content_scope: "core", published_at: FRESH.ago
    )

    PurgeStaleDataJob.perform_now

    assert NewsArticle.exists?(fresh_article.id)
    assert NewsIngest.exists?(ingest.id), "ingest is still referenced and must survive"
  end

  # Slow-moving context is not observational data. ConflictEvent especially:
  # AreaReport and ConnectionFinder both query it 90 days back.
  test "leaves reference data alone" do
    conflict = ConflictEvent.create!(external_id: 90_001, latitude: 10, longitude: 10, created_at: STALE.ago)
    price = CommodityPrice.create!(
      symbol: "BZ=F", category: "commodity", name: "Brent", recorded_at: STALE.ago
    )
    trade = TradeFlowSnapshot.create!(
      reporter_country_code_alpha3: "DEU", partner_country_code_alpha3: "FRA",
      flow_direction: "import", commodity_key: "crude", period_type: "annual",
      period_start: 2.years.ago.to_date, source: "comtrade", dataset: "hs", raw_payload: {}
    )

    PurgeStaleDataJob.perform_now

    assert ConflictEvent.exists?(conflict.id)
    assert CommodityPrice.exists?(price.id)
    assert TradeFlowSnapshot.exists?(trade.id)
  end

  # These hold one upserted row per vehicle rather than history, so they run on
  # much shorter clocks than the retention window.
  test "live state tables follow their own freshness windows" do
    fresh_flight = Flight.create!(icao24: "live01", military: false, updated_at: 2.hours.ago)
    stale_flight = Flight.create!(icao24: "live02", military: false, updated_at: 8.hours.ago)
    fresh_ship = Ship.create!(mmsi: "111111111", updated_at: 12.hours.ago)
    stale_ship = Ship.create!(mmsi: "222222222", updated_at: 30.hours.ago)

    PurgeStaleDataJob.perform_now

    assert Flight.exists?(fresh_flight.id)
    assert_not Flight.exists?(stale_flight.id)
    assert Ship.exists?(fresh_ship.id)
    assert_not Ship.exists?(stale_ship.id)
  end

  # delete_all skips `dependent: :destroy`, and timeline_events has no foreign
  # key, so a fresh child of a purged parent would otherwise linger forever.
  test "sweeps polymorphic children orphaned by a purged parent" do
    doomed = FireHotspot.create!(external_id: "fire-orphan", latitude: 3, longitude: 3, acq_datetime: STALE.ago)
    orphan = TimelineEvent.create!(
      event_type: "fire", eventable: doomed, recorded_at: FRESH.ago
    )
    survivor_parent = FireHotspot.create!(external_id: "fire-keep", latitude: 4, longitude: 4, acq_datetime: FRESH.ago)
    survivor = TimelineEvent.create!(
      event_type: "fire", eventable: survivor_parent, recorded_at: FRESH.ago
    )

    PurgeStaleDataJob.perform_now

    assert_not FireHotspot.exists?(doomed.id)
    assert_not TimelineEvent.exists?(orphan.id), "timeline event outlived its purged parent"
    assert TimelineEvent.exists?(survivor.id), "timeline event with a live parent must stay"
  end

  # The backstop for the flight/ship churn: the pollers delete stale rows with
  # delete_all, which skips the `dependent: :delete_all` on Flight, so the links
  # they leave behind have no owner and no foreign key to catch them.
  test "sweeps entity links orphaned by a purged flight" do
    doomed = Flight.create!(icao24: "orph01", military: false, updated_at: 8.hours.ago)
    survivor = Flight.create!(icao24: "orph02", military: false, updated_at: 2.hours.ago)
    entity = OperationalOntologySyncService.sync_flight(doomed)
    kept_entity = OperationalOntologySyncService.sync_flight(survivor)

    deleted = PurgeStaleDataJob.perform_now

    assert_not Flight.exists?(doomed.id)
    assert_not OntologyEntityLink.exists?(ontology_entity: entity, linkable_type: "Flight", linkable_id: doomed.id),
      "entity link outlived the flight it points at"
    assert OntologyEntityLink.exists?(ontology_entity: kept_entity, linkable: survivor, role: "tracked_flight"),
      "link with a live flight must stay"
    assert_equal 1, deleted[:ontology_entity_links_orphaned]
  end

  # Guards the catch-up path: production carries an 8.6M row backlog in
  # position_snapshots, and one run must not try to swallow it whole.
  test "caps how much a single table can delete in one run and records that it capped" do
    ids = 3.times.map { |i| position_snapshot("capped#{i}", STALE.ago) }.map(&:id)
    job = PurgeStaleDataJob.new
    job.instance_variable_set(:@capped, [])

    deleted = job.send(:delete_in_batches, PositionSnapshot.where(id: ids), budget: 2)

    assert_equal 2, deleted
    assert_equal 1, PositionSnapshot.where(id: ids).count, "remainder waits for the next run"
    assert_includes job.instance_variable_get(:@capped), "position_snapshots"
  end

  test "reports what it removed per table" do
    position_snapshot("counted", STALE.ago)

    deleted = PurgeStaleDataJob.perform_now

    assert_equal 1, deleted[:position_snapshots]
  end

  # The orphan sweep and the observation pass both touch timeline_events;
  # merging them under one key would silently drop a count.
  test "counts orphan sweeps separately from the observation pass" do
    doomed = FireHotspot.create!(external_id: "fire-count", latitude: 5, longitude: 5, acq_datetime: STALE.ago)
    TimelineEvent.create!(event_type: "fire", eventable: doomed, recorded_at: FRESH.ago)
    TimelineEvent.create!(event_type: "quake", eventable: doomed.dup.tap { |f|
      f.external_id = "fire-count-2"
      f.acq_datetime = FRESH.ago
      f.save!
    }, recorded_at: STALE.ago)

    deleted = PurgeStaleDataJob.perform_now

    assert_equal 1, deleted[:timeline_events], "stale-by-own-clock timeline event"
    assert_equal 1, deleted[:timeline_events_orphaned], "fresh event whose parent was purged"
  end

  private

  def position_snapshot(entity_id, recorded_at)
    PositionSnapshot.create!(
      entity_type: "flight", entity_id: entity_id,
      latitude: 48.0, longitude: 16.0, recorded_at: recorded_at
    )
  end
end
