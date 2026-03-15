module RefreshableDataService
  extend ActiveSupport::Concern

  # Template method for the refresh cycle shared by data-fetching services.
  #
  # Including classes must implement:
  #   fetch_data       — fetch raw data from external source, return it (or nil to abort)
  #   parse_records(data) — transform raw data into an array of attribute hashes
  #   upsert_records(records) — persist records to the database
  #
  # Including classes may override:
  #   after_upsert(records) — hook for cleanup or extra work after upsert (default: no-op)
  #   timeline_config       — return a hash with :event_type and :time_column for timeline recording
  #                           Return nil to skip timeline recording.
  #   unique_key            — the column used for upsert uniqueness (default: :external_id)

  def refresh
    data = fetch_data
    return 0 unless data

    records = parse_records(data)
    return 0 if records.blank?

    upsert_records(records)
    after_upsert(records)

    tl = timeline_config
    if tl
      record_timeline_events(
        event_type: tl[:event_type],
        model_class: tl[:model_class],
        unique_key: unique_key,
        unique_values: records.map { |r| r[unique_key] },
        time_column: tl[:time_column]
      )
    end

    records.size
  rescue StandardError => e
    Rails.logger.error("#{self.class.name}: #{e.message}")
    0
  end

  private

  def unique_key
    :external_id
  end

  def after_upsert(records)
    # no-op by default; override in subclass if needed
  end

  def timeline_config
    # Override to return { event_type: "...", model_class: Model, time_column: :col }
    nil
  end
end
