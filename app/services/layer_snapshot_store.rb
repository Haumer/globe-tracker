class LayerSnapshotStore
  class << self
    def fetch(snapshot_type:, scope_key: "global")
      LayerSnapshot.find_by(snapshot_type: snapshot_type.to_s, scope_key: scope_key.to_s)
    end

    def persist(snapshot_type:, payload:, expires_in:, scope_key: "global", metadata: {}, fetched_at: Time.current)
      snapshot = LayerSnapshot.find_or_initialize_by(
        snapshot_type: snapshot_type.to_s,
        scope_key: scope_key.to_s,
      )

      snapshot.assign_attributes(
        payload: payload || {},
        metadata: metadata || {},
        status: "ready",
        error_code: nil,
        fetched_at: fetched_at,
        expires_at: fetched_at + expires_in,
      )
      snapshot.save!
      snapshot
    end

    def persist_error(snapshot_type:, error_code:, expires_in:, scope_key: "global", metadata: {}, fetched_at: Time.current)
      snapshot = LayerSnapshot.find_or_initialize_by(
        snapshot_type: snapshot_type.to_s,
        scope_key: scope_key.to_s,
      )

      snapshot.payload = {} if snapshot.new_record?
      snapshot.metadata = (snapshot.metadata || {}).merge(metadata || {})
      snapshot.status = "error"
      snapshot.error_code = error_code.to_s.first(255)
      snapshot.fetched_at = fetched_at
      snapshot.expires_at = fetched_at + expires_in
      snapshot.save!
      snapshot
    end
  end
end
