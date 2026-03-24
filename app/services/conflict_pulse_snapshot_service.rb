class ConflictPulseSnapshotService
  SNAPSHOT_TYPE = "conflict_pulse".freeze
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
      ConflictPulseService.invalidate
      payload = ConflictPulseService.analyze
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
      { zones: [], strike_arcs: [], hex_cells: [] }
    end

    private

    def enqueue_refresh
      BackgroundRefreshScheduler.enqueue_once(
        RefreshConflictPulseSnapshotJob,
        key: "snapshot:#{SNAPSHOT_TYPE}:#{SCOPE_KEY}",
        ttl: 1.minute,
      )
    end
  end
end
