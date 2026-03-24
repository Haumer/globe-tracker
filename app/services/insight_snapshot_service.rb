class InsightSnapshotService
  SNAPSHOT_TYPE = "insights".freeze
  SCOPE_KEY = "global".freeze
  TTL = 5.minutes

  class << self
    def fetch_or_enqueue
      snapshot = LayerSnapshotStore.fetch(snapshot_type: SNAPSHOT_TYPE, scope_key: SCOPE_KEY)
      return snapshot if snapshot&.fresh?

      enqueue_refresh
      snapshot
    end

    def refresh
      payload = { insights: CrossLayerAnalyzer.analyze }
      LayerSnapshotStore.persist(
        snapshot_type: SNAPSHOT_TYPE,
        scope_key: SCOPE_KEY,
        payload: payload,
        expires_in: TTL,
      )
    rescue StandardError => e
      LayerSnapshotStore.persist_error(
        snapshot_type: SNAPSHOT_TYPE,
        scope_key: SCOPE_KEY,
        error_code: "#{e.class}: #{e.message}",
        expires_in: 1.minute,
      )
      raise
    end

    def empty_payload
      { insights: [] }
    end

    private

    def enqueue_refresh
      BackgroundRefreshScheduler.enqueue_once(
        RefreshInsightsSnapshotJob,
        key: "snapshot:#{SNAPSHOT_TYPE}:#{SCOPE_KEY}",
        ttl: 1.minute,
      )
    end
  end
end
