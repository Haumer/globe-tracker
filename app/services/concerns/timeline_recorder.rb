module TimelineRecorder
  extend ActiveSupport::Concern

  private

  # Records timeline events for a batch of upserted records.
  # After upsert_all we don't get IDs back, so we query by the unique key.
  #
  # Example:
  #   record_timeline_events(
  #     event_type: "earthquake",
  #     model_class: Earthquake,
  #     unique_key: :external_id,
  #     unique_values: records.map { |r| r[:external_id] },
  #     time_column: :event_time
  #   )
  def record_timeline_events(event_type:, model_class:, unique_key:, unique_values:, time_column:)
    return if unique_values.blank?

    inserted = model_class.where(unique_key => unique_values)
                          .where.not(latitude: nil, longitude: nil)
                          .select(:id, :latitude, :longitude, time_column)

    rows = inserted.filter_map do |record|
      {
        event_type: event_type,
        eventable_type: model_class.name,
        eventable_id: record.id,
        latitude: record.latitude,
        longitude: record.longitude,
        recorded_at: record.send(time_column) || Time.current,
        created_at: Time.current,
        updated_at: Time.current,
      }
    end

    TimelineEvent.upsert_all(rows, unique_by: [:eventable_type, :eventable_id]) if rows.any?
  rescue => e
    Rails.logger.error("Timeline recording error (#{event_type}): #{e.message}")
  end
end
