class PollingStatRecorder
  class << self
    def record(source:, poll_type:, status:, records_fetched: 0, records_stored: nil, duration_ms: 0, error_message: nil, created_at: Time.current)
      return if source.blank? || poll_type.blank?

      PollingStat.create!(
        source: source.to_s,
        poll_type: poll_type.to_s,
        records_fetched: records_fetched.to_i,
        records_stored: (records_stored.nil? ? records_fetched : records_stored).to_i,
        duration_ms: duration_ms.to_i,
        status: status.to_s,
        error_message: error_message&.to_s&.first(1000),
        created_at: created_at,
      )
    rescue StandardError => e
      Rails.logger.warn("PollingStatRecorder: #{e.message}")
      nil
    end
  end
end
