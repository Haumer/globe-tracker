class SourceFeedStatusRecorder
  class << self
    def record(provider:, display_name:, feed_kind:, endpoint_url:, status:, records_fetched: 0, records_stored: 0, http_status: nil, error_message: nil, metadata: {}, occurred_at: Time.current)
      return if provider.blank? || display_name.blank? || feed_kind.blank?

      key = feed_key(provider: provider, display_name: display_name, endpoint_url: endpoint_url)
      now = occurred_at || Time.current

      attrs = {
        provider: provider.to_s,
        display_name: display_name.to_s,
        feed_kind: feed_kind.to_s,
        endpoint_url: endpoint_url.to_s.presence,
        status: status.to_s,
        last_http_status: http_status.presence&.to_i,
        last_records_fetched: records_fetched.to_i,
        last_records_stored: records_stored.to_i,
        last_error_message: error_message.to_s.first(1000).presence,
        metadata: (metadata || {}).deep_stringify_keys,
        updated_at: now
      }

      if status.to_s == "success"
        attrs[:last_success_at] = now
      elsif status.to_s == "error"
        attrs[:last_error_at] = now
      end

      record = SourceFeedStatus.find_or_initialize_by(feed_key: key)
      record.assign_attributes(attrs)
      record.save!
      record
    rescue StandardError => e
      Rails.logger.warn("SourceFeedStatusRecorder: #{e.message}")
      nil
    end

    private

    def feed_key(provider:, display_name:, endpoint_url:)
      token = endpoint_url.to_s.presence || display_name.to_s.parameterize
      "#{provider}:#{token}"
    end
  end
end
