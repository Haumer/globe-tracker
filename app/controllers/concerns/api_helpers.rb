module ApiHelpers
  extend ActiveSupport::Concern

  private

  def parse_bounds
    { lamin: params[:lamin]&.to_f, lamax: params[:lamax]&.to_f,
      lomin: params[:lomin]&.to_f, lomax: params[:lomax]&.to_f }.compact
  end

  def parse_time_range(default_from: 24.hours.ago, default_to: Time.current)
    if params[:from].present? && params[:to].present?
      from = Time.parse(params[:from]) rescue default_from
      to = Time.parse(params[:to]) rescue default_to
      [from, to]
    end
  end

  # Scope helper: applies time range if provided, otherwise uses .recent
  def time_scoped(model)
    range = parse_time_range
    range ? model.in_range(*range) : model.recent
  end

  def parse_json_field(value)
    return value if value.is_a?(Array)
    return [] if value.blank?
    value.is_a?(String) ? JSON.parse(value) : (value || [])
  end

  def safe_thread_value(thread, label, fallback = [])
    thread.value
  rescue StandardError => e
    Rails.logger.error("#{label} thread error: #{e.message}")
    fallback
  end
end
