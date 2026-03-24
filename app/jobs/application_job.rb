class ApplicationJob < ActiveJob::Base
  class_attribute :polling_source_resolver, instance_writer: false, default: nil
  class_attribute :polling_type_resolver, instance_writer: false, default: nil

  around_perform :record_polling_telemetry

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  def self.tracks_polling(source:, poll_type:)
    self.polling_source_resolver = source
    self.polling_type_resolver = poll_type
  end

  private

  def record_polling_telemetry
    source = resolve_polling_value(self.class.polling_source_resolver)
    poll_type = resolve_polling_value(self.class.polling_type_resolver)
    return yield if source.blank? || poll_type.blank?

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    result = yield
    record_polling_stat(
      source: source,
      poll_type: poll_type,
      status: "success",
      result: result,
      duration_ms: elapsed_ms_since(started_at),
    )
    result
  rescue StandardError => e
    record_polling_stat(
      source: source,
      poll_type: poll_type,
      status: "error",
      result: nil,
      duration_ms: elapsed_ms_since(started_at),
      error_message: "#{e.class}: #{e.message}",
    )
    raise
  end

  def resolve_polling_value(resolver)
    case resolver
    when Proc
      resolver.call(self, arguments)
    when Symbol
      public_send(resolver)
    else
      resolver
    end
  end

  def elapsed_ms_since(started_at)
    return 0 unless started_at

    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
  rescue StandardError
    0
  end

  def record_polling_stat(source:, poll_type:, status:, result:, duration_ms:, error_message: nil)
    records_fetched, records_stored = extract_record_counts(result)
    PollingStatRecorder.record(
      source: source,
      poll_type: poll_type,
      status: status,
      records_fetched: records_fetched,
      records_stored: records_stored,
      duration_ms: duration_ms,
      error_message: error_message,
    )
  end

  def extract_record_counts(result)
    case result
    when Hash
      fetched = result[:records_fetched] || result["records_fetched"] || result[:count] || result["count"] || 0
      stored = result[:records_stored] || result["records_stored"] || fetched
      [fetched.to_i, stored.to_i]
    when Integer
      [result, result]
    when NilClass
      [0, 0]
    else
      size = result.respond_to?(:size) ? result.size : 0
      [size.to_i, size.to_i]
    end
  rescue StandardError
    [0, 0]
  end
end
