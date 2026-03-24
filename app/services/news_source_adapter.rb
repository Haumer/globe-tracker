class NewsSourceAdapter
  class << self
    def normalize!(source_adapter:, attrs:)
      normalized = new(source_adapter: source_adapter, attrs: attrs).normalize
      raise ArgumentError, "news source adapter requires url and title" if normalized[:url].blank? || normalized[:title].blank?

      normalized
    end
  end

  def initialize(source_adapter:, attrs:)
    @source_adapter = source_adapter
    @attrs = (attrs || {}).to_h.symbolize_keys
  end

  def normalize
    {
      source_adapter: @source_adapter.to_s,
      url: scrub_string(@attrs[:url], 2000),
      title: scrub_string(@attrs[:title], 500),
      summary: scrub_string(@attrs[:summary], 20_000),
      name: scrub_string(@attrs[:name], 200),
      country: scrub_string(@attrs[:country], 100),
      tone: normalize_number(@attrs[:tone]),
      published_at: @attrs[:published_at],
      themes: normalize_array(@attrs[:themes]),
      category: scrub_string(@attrs[:category], 100),
      source: scrub_string(@attrs[:source], 100),
      metadata: normalize_metadata(@attrs[:metadata]),
    }
  end

  private

  def scrub_string(value, max_length)
    return nil if value.blank?

    value.to_s.scrub("").strip.first(max_length).presence
  end

  def normalize_array(value)
    Array(value).filter_map do |item|
      scrub_string(item, 100)
    end.uniq
  end

  def normalize_number(value)
    return nil if value.nil?

    Float(value)
  rescue ArgumentError, TypeError
    nil
  end

  def normalize_metadata(value)
    return {} unless value.is_a?(Hash)

    value.each_with_object({}) do |(key, item), metadata|
      next if item.nil?

      metadata[key.to_s] = item.is_a?(String) ? item.to_s.scrub("").strip : item
    end
  end
end
