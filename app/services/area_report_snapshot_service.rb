class AreaReportSnapshotService
  SNAPSHOT_TYPE = "area_report".freeze
  TTL = 2.minutes

  class << self
    def fetch(bounds)
      LayerSnapshotStore.fetch(
        snapshot_type: SNAPSHOT_TYPE,
        scope_key: scope_key_for(bounds),
      )
    end

    def refresh(bounds)
      normalized_bounds = normalize_bounds(bounds)
      payload = AreaReport.generate(normalized_bounds)

      LayerSnapshotStore.persist(
        snapshot_type: SNAPSHOT_TYPE,
        scope_key: scope_key_for(normalized_bounds),
        payload: payload,
        metadata: { bounds: normalized_bounds },
        expires_in: TTL,
      )
    rescue StandardError => e
      LayerSnapshotStore.persist_error(
        snapshot_type: SNAPSHOT_TYPE,
        scope_key: scope_key_for(bounds),
        metadata: { bounds: normalize_bounds(bounds) },
        error_code: "#{e.class}: #{e.message}",
        expires_in: 1.minute,
      )
      raise
    end

    def enqueue_refresh(bounds)
      normalized_bounds = normalize_bounds(bounds)
      scope_key = scope_key_for(normalized_bounds)

      BackgroundRefreshScheduler.enqueue_once(
        RefreshAreaReportSnapshotJob,
        normalized_bounds,
        key: "snapshot:#{SNAPSHOT_TYPE}:#{scope_key}",
        ttl: 30.seconds,
      )
    end

    def scope_key_for(bounds)
      normalized = normalize_bounds(bounds)
      "bbox:#{normalized[:lamin]},#{normalized[:lamax]},#{normalized[:lomin]},#{normalized[:lomax]}"
    end

    def normalize_bounds(bounds)
      {
        lamin: bounds[:lamin].to_f.round(1),
        lamax: bounds[:lamax].to_f.round(1),
        lomin: bounds[:lomin].to_f.round(1),
        lomax: bounds[:lomax].to_f.round(1),
      }
    end
  end
end
