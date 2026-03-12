require "set"

class NewsRefreshService
  include TimelineRecorder

  FEED_URL = "https://api.gdeltproject.org/api/v1/gkg_geojson".freeze
  REFRESH_INTERVAL = 15.minutes
  INTERESTING_THEMES = %w[
    ARMEDCONFLICT PROTEST TERROR ECON_BANKRUPTCY ECON_STOCKMARKET
    ENV_EARTHQUAKE ENV_VOLCANO ENV_FLOOD ENV_HURRICANE ENV_WILDFIRE
    HEALTH_PANDEMIC HEALTH_EPIDEMIC CYBER_ATTACK LEADER
    DISPLACEMENT REFUGEE FAMINE ASSASSINATION ARREST
    MILITARY REBELLION COUP CEASEFIRE PEACE
    GENERAL_HEALTH MEDICAL EPU_CATS_NATIONAL_SECURITY
    WB_695_POVERTY CRISIS
  ].freeze

  class << self
    def refresh_if_stale(force: false)
      return 0 if !force && !stale?

      new.refresh
    end

    def stale?
      latest_fetch_at.blank? || latest_fetch_at < REFRESH_INTERVAL.ago
    end

    def latest_fetch_at
      NewsEvent.maximum(:fetched_at)
    end
  end

  def refresh
    uri = URI(FEED_URL)
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      http.request(Net::HTTP::Get.new(uri))
    end
    return 0 unless response.is_a?(Net::HTTPSuccess)

    body = response.body.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    data = JSON.parse(body)
    features = data["features"] || []
    now = Time.current
    seen_urls = Set.new
    records = []

    features.each do |feature|
      coords = feature.dig("geometry", "coordinates")
      props = feature["properties"] || {}
      url = props["url"]

      next if coords.nil? || coords.length < 2
      next if url.blank? || seen_urls.include?(url)

      seen_urls.add(url)

      lng = coords[0].to_f
      lat = coords[1].to_f
      next if lat == 0.0 && lng == 0.0

      themes_raw = (props["mentionedthemes"] || "").split(";").map(&:strip).reject(&:blank?).uniq
      matched_themes = themes_raw.select { |theme| INTERESTING_THEMES.any? { |candidate| theme.include?(candidate) } }
      next if matched_themes.empty?

      tone = props["urltone"]&.to_f || 0.0
      published_at = begin
        props["urlpubtimedate"].present? ? Time.parse(props["urlpubtimedate"]) : nil
      rescue StandardError
        nil
      end

      records << {
        url: url,
        name: props["name"],
        title: props["name"],
        latitude: lat,
        longitude: lng,
        tone: tone.round(1),
        level: tone_level(tone),
        category: categorize(matched_themes),
        themes: matched_themes.first(5),
        published_at: published_at,
        fetched_at: now,
        source: "gdelt",
        created_at: now,
        updated_at: now,
      }
    end

    records.each do |record|
      record.each { |key, value| record[key] = value.scrub("") if value.is_a?(String) }
    end

    return 0 if records.empty?

    NewsEvent.upsert_all(records, unique_by: :url)
    record_timeline_events(
      event_type: "news",
      model_class: NewsEvent,
      unique_key: :url,
      unique_values: records.map { |record| record[:url] },
      time_column: :published_at
    )

    records.size
  rescue StandardError => e
    Rails.logger.error("NewsRefreshService: #{e.message}")
    0
  end

  private

  def tone_level(tone)
    if tone <= -5
      "critical"
    elsif tone <= -2
      "negative"
    elsif tone <= 2
      "neutral"
    else
      "positive"
    end
  end

  def categorize(themes)
    if themes.any? { |theme| theme.include?("ARMEDCONFLICT") || theme.include?("MILITARY") || theme.include?("TERROR") }
      "conflict"
    elsif themes.any? { |theme| theme.include?("PROTEST") || theme.include?("REBELLION") || theme.include?("COUP") }
      "unrest"
    elsif themes.any? { |theme| theme.include?("ENV_") || theme.include?("EARTHQUAKE") || theme.include?("VOLCANO") || theme.include?("FLOOD") || theme.include?("WILDFIRE") || theme.include?("HURRICANE") }
      "disaster"
    elsif themes.any? { |theme| theme.include?("HEALTH") || theme.include?("PANDEMIC") || theme.include?("EPIDEMIC") || theme.include?("MEDICAL") }
      "health"
    elsif themes.any? { |theme| theme.include?("ECON_") || theme.include?("POVERTY") || theme.include?("FAMINE") }
      "economy"
    elsif themes.any? { |theme| theme.include?("PEACE") || theme.include?("CEASEFIRE") }
      "diplomacy"
    else
      "other"
    end
  end
end
