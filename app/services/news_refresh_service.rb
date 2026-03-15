require "set"

class NewsRefreshService
  extend Refreshable
  include TimelineRecorder
  include NewsDedupable

  FEED_URL = "https://api.gdeltproject.org/api/v1/gkg_geojson".freeze
  INTERESTING_THEMES = %w[
    ARMEDCONFLICT PROTEST TERROR ECON_BANKRUPTCY ECON_STOCKMARKET
    ENV_EARTHQUAKE ENV_VOLCANO ENV_FLOOD ENV_HURRICANE ENV_WILDFIRE
    HEALTH_PANDEMIC HEALTH_EPIDEMIC CYBER_ATTACK LEADER
    DISPLACEMENT REFUGEE FAMINE ASSASSINATION ARREST
    MILITARY REBELLION COUP CEASEFIRE PEACE
    GENERAL_HEALTH MEDICAL EPU_CATS_NATIONAL_SECURITY
    WB_695_POVERTY CRISIS
  ].freeze

  refreshes model: NewsEvent, interval: 15.minutes

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

      # GDELT GeoJSON "name" is the location, not the article title.
      # Extract a meaningful title from the URL path as fallback.
      location_name = props["name"]
      title = extract_title_from_url(url) || location_name
      # Skip records where we only have a bare location name (no real headline)
      next if title == location_name && title.present? && title.split(",").first.strip.split.size < 4

      records << {
        url: url,
        name: location_name,
        title: title,
        latitude: lat,
        longitude: lng,
        tone: tone.round(1),
        level: ThreatClassifier.tone_level(tone),
        category: ThreatClassifier.categorize_themes(matched_themes),
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

    assign_clusters(records)
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

  # Extract a readable title from a URL slug (e.g., /2024/03/earthquake-hits-turkey → "Earthquake Hits Turkey")
  def extract_title_from_url(url)
    path = begin; URI(url).path; rescue; return nil; end
    slug = path.split("/").last
    return nil if slug.blank? || slug.match?(/\A\d+\z/) || slug.length < 10

    words = slug.gsub(/\.\w+\z/, "")           # strip file extension
                .gsub(/[-_]/, " ")               # dashes/underscores → spaces
                .gsub(/\b[a-f0-9]{8,}\b/, "")   # strip hex IDs
                .gsub(/\b\d{5,}\b/, "")          # strip long numeric IDs
                .strip
    return nil if words.split.size < 3

    words.split.map(&:capitalize).join(" ")
  end
end
