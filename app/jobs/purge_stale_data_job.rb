class PurgeStaleDataJob < ApplicationJob
  queue_as :background

  # Deletes run in chunks so a large backlog never holds a single long
  # transaction open against the live write path.
  DELETE_BATCH_SIZE = 25_000

  # Ceiling per table per run. Sized well above steady state — position_
  # snapshots peaks around 300k/hour — so this only bites while draining a
  # backlog, spreading a multi-million-row catch-up across several hourly
  # passes instead of one very long job.
  MAX_DELETES_PER_TABLE = 1_000_000

  def perform(now: Time.current)
    cutoff = DataRetention.cutoff(now: now)
    @capped = []

    deleted = purge_news_graph(cutoff)
      .merge(purge_train_graph(cutoff))
      .merge(purge_observations(cutoff))
      .merge(purge_live_state(now: now, cutoff: cutoff))
      .merge(purge_orphans)

    Rails.logger.info(
      "PurgeStaleDataJob: removed #{deleted.values.sum} rows outside the " \
      "#{DataRetention.days}-day window #{deleted.reject { |_, count| count.zero? }.inspect}"
    )
    if @capped.any?
      Rails.logger.warn(
        "PurgeStaleDataJob: hit the #{MAX_DELETES_PER_TABLE}-row per-run cap on " \
        "#{@capped.uniq.join(', ')} — backlog remains, next run continues"
      )
    end

    deleted
  end

  private

  # Observational tables: append-only rows the pollers emit that nothing edits
  # afterwards. Reference data is deliberately absent — the ontology graph,
  # gazetteers, trade_flow_snapshots and commodity_prices are slow-moving
  # context that has to outlive the observation window, and ConflictEvent in
  # particular is queried 90 days back by AreaReport and ConnectionFinder.
  def observation_tables
    [
      [PositionSnapshot, :recorded_at],
      [FireHotspot, :acq_datetime],
      [TimelineEvent, :recorded_at],
      [GeoconfirmedEvent, :event_time],
      [Earthquake, :event_time],
      [PollingStat, :created_at],
      [GpsJammingSnapshot, :recorded_at],
      [InternetTrafficSnapshot, :created_at],
      [InternetAttackPairSnapshot, :created_at],
      [SatelliteTleSnapshot, :recorded_at],
    ]
  end

  def purge_observations(cutoff)
    observation_tables.to_h do |model, column|
      [model.table_name.to_sym, delete_in_batches(model.where(column => ...cutoff))]
    end
  end

  # news_ingests -> news_articles -> {news_claims -> news_claim_actors,
  # news_events, news_story_memberships}, with news_story_clusters pointing
  # back at a lead article and ontology_events pointing at a cluster.
  #
  # Nothing here is declared ON DELETE CASCADE, so children are removed by
  # reference to their stale parent rather than by their own timestamp: a
  # claim can carry a newer published_at than the article it hangs off, and
  # deleting that article underneath it would trip the foreign key mid-purge.
  def purge_news_graph(cutoff)
    counts = Hash.new(0)
    stale_articles = NewsArticle.where(published_at: ...cutoff)
    article_ids = stale_articles.select(:id)

    counts[:news_claim_actors] += delete_in_batches(
      NewsClaimActor.where(news_claim_id: NewsClaim.where(news_article_id: article_ids).select(:id))
    )
    counts[:news_claims] += delete_in_batches(NewsClaim.where(news_article_id: article_ids))
    counts[:news_events] += delete_in_batches(NewsEvent.where(news_article_id: article_ids))
    counts[:news_story_memberships] += delete_in_batches(NewsStoryMembership.where(news_article_id: article_ids))
    # lead_news_article_id is nullable — a cluster outlives any single article.
    NewsStoryCluster.where(lead_news_article_id: article_ids).update_all(lead_news_article_id: nil)
    counts[:news_articles] += delete_in_batches(stale_articles)

    # Events that never resolved to an article age out on their own clock.
    counts[:news_events] += delete_in_batches(
      NewsEvent.where(news_article_id: nil).where(published_at: ...cutoff)
    )

    stale_clusters = NewsStoryCluster.where(last_seen_at: ...cutoff)
    cluster_ids = stale_clusters.select(:id)
    counts[:news_story_memberships] += delete_in_batches(
      NewsStoryMembership.where(news_story_cluster_id: cluster_ids)
    )
    # news_events.story_cluster_id is a *string* holding the cluster_key, not
    # a foreign key on id. Null it so surviving events do not dangle at a
    # deleted cluster.
    NewsEvent.where(story_cluster_id: stale_clusters.select(:cluster_key)).update_all(story_cluster_id: nil)
    OntologyEvent.where(primary_story_cluster_id: cluster_ids).update_all(primary_story_cluster_id: nil)
    counts[:news_story_clusters] += delete_in_batches(stale_clusters)

    # Raw payload table, 8.9 GB in production. Only drop an ingest once
    # nothing still points at it — articles can outlive their fetch batch.
    # The NOT IN subqueries exclude NULLs explicitly: a single NULL would
    # otherwise make the whole predicate unknown and delete nothing.
    counts[:news_ingests] += delete_in_batches(
      NewsIngest.where(fetched_at: ...cutoff)
        .where.not(id: NewsArticle.where.not(news_ingest_id: nil).select(:news_ingest_id))
        .where.not(id: NewsEvent.where.not(news_ingest_id: nil).select(:news_ingest_id))
    )

    # Actors are only reachable through claims; drop the ones nothing cites.
    counts[:news_actors] += delete_in_batches(
      NewsActor.where(created_at: ...cutoff).where.not(id: NewsClaimActor.select(:news_actor_id))
    )

    counts
  end

  def purge_train_graph(cutoff)
    counts = Hash.new(0)
    stale_ingests = TrainIngest.where(fetched_at: ...cutoff)

    counts[:train_observations] += delete_in_batches(
      TrainObservation.where(train_ingest_id: stale_ingests.select(:id))
    )
    counts[:train_observations] += delete_in_batches(
      TrainObservation.where(train_ingest_id: nil).where(fetched_at: ...cutoff)
    )
    counts[:train_ingests] += delete_in_batches(stale_ingests)

    counts
  end

  # Current-state and already-expired rows, which follow their own clocks
  # rather than the retention window. See DataRetention for why.
  def purge_live_state(now:, cutoff:)
    {
      flights: delete_in_batches(Flight.where(updated_at: ...(now - DataRetention::LIVE_FLIGHT_WINDOW))),
      ships: delete_in_batches(Ship.where(updated_at: ...(now - DataRetention::LIVE_SHIP_WINDOW))),
      cameras: delete_in_batches(Camera.where(expires_at: ...now)),
      weather_alerts: delete_in_batches(WeatherAlert.where(expires: ...cutoff)),
      notams: delete_in_batches(Notam.where(effective_end: ...cutoff)),
    }
  end

  # Polymorphic children of the tables above. delete_all bypasses the
  # `dependent:` callbacks that would normally clear these, and neither table
  # has a foreign key to fall back on — so a child whose own timestamp is
  # newer than its parent's would outlive that parent indefinitely. Runs last,
  # once every parent delete above has committed.
  def orphan_sweeps
    [
      [TimelineEvent, :eventable_type, :eventable_id],
      [OntologyEvidenceLink, :evidence_type, :evidence_id],
      [OntologyEntityLink, :linkable_type, :linkable_id],
    ]
  end

  def purge_orphans
    counts = Hash.new(0)

    orphan_sweeps.each do |model, type_column, id_column|
      model.distinct.pluck(type_column).compact.each do |type_name|
        owner = type_name.safe_constantize
        # A type we can no longer resolve is left alone on purpose: deleting
        # rows on behalf of an unknown class is not a call this job should make.
        next unless owner.respond_to?(:primary_key)

        # Distinct key from the observation pass, which already reports
        # timeline_events under its own name — merging would drop one count.
        counts[:"#{model.table_name}_orphaned"] += delete_in_batches(
          model.where(type_column => type_name).where.not(id_column => owner.select(:id))
        )
      end
    end

    counts
  end

  # Chunked so no single statement holds a long lock, and capped so one table
  # with a large backlog cannot monopolise the run. Anything left over is
  # picked up by the next hourly pass rather than silently forgotten.
  def delete_in_batches(relation, budget: MAX_DELETES_PER_TABLE)
    deleted = 0

    while deleted < budget
      batch = relation.limit([DELETE_BATCH_SIZE, budget - deleted].min).delete_all
      deleted += batch
      break if batch.zero?
    end

    if deleted >= budget
      @capped << relation.klass.table_name
    end

    deleted
  end
end
