require "set"

class NewsRefreshService
  extend Refreshable
  include TimelineRecorder
  include NewsDedupable

  FEED_URL = "https://api.gdeltproject.org/api/v1/gkg_geojson".freeze

  # Targeted conflict queries — GDELT DOC API with GeoJSON output
  # Each returns geocoded articles matching strike/conflict terms for active theaters
  CONFLICT_QUERIES = [
    "Iran strike OR Iran attack OR Iran bomb OR IRGC OR Tehran missile",
    "Gaza strike OR Gaza bomb OR IDF OR Hamas rocket OR Rafah",
    "Ukraine strike OR Ukraine missile OR Kyiv drone OR Kharkiv shelling",
    "Yemen Houthi OR Red Sea attack OR Bab el-Mandeb",
    "Lebanon Hezbollah OR Beirut strike OR Israel border",
    "Syria airstrike OR Syria bomb OR Damascus",
    "Sudan RSF OR Khartoum fighting OR Sudan war",
  ].freeze

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
    ingest_items = []

    features.each_with_index do |feature, idx|
      coords = feature.dig("geometry", "coordinates")
      props = feature["properties"] || {}
      url = props["url"]
      location_name = props["name"]
      raw_title = props["title"] || extract_title_from_url(url) || location_name
      ingest_items << {
        item_key: url.presence || "gdelt-geojson-#{idx}",
        source_feed: "gdelt",
        source_endpoint_url: FEED_URL,
        external_id: props["gkgrecordid"] || props["gkgrecordid"],
        raw_url: url,
        raw_title: raw_title,
        raw_summary: props["summary"] || props["snippet"],
        raw_published_at: props["urlpubtimedate"],
        fetched_at: now,
        payload_format: "json",
        raw_payload: feature,
        http_status: response.code.to_i,
      }

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
      title = extract_title_from_url(url) || location_name
      # Skip records where we only have a bare location name (no real headline)
      next if title == location_name && title.present? && title.split(",").first.strip.split.size < 4

      adapted = NewsSourceAdapter.normalize!(
        source_adapter: "gdelt_geojson",
        attrs: {
          url: url,
          title: title,
          summary: props["summary"] || props["snippet"],
          name: location_name,
          published_at: published_at,
          category: ThreatClassifier.categorize_themes(matched_themes),
          themes: matched_themes.first(5),
          source: "gdelt",
        }
      )

      records << {
        url: adapted[:url],
        name: adapted[:name],
        title: adapted[:title],
        latitude: lat,
        longitude: lng,
        tone: tone.round(1),
        level: ThreatClassifier.tone_level(tone),
        category: adapted[:category],
        themes: adapted[:themes],
        published_at: adapted[:published_at],
        fetched_at: now,
        source: "gdelt",
        created_at: now,
        updated_at: now,
      }
    end

    # Also fetch targeted conflict queries for active theaters
    conflict_result = fetch_conflict_queries(seen_urls, now)
    conflict_records = conflict_result[:records]
    records.concat(conflict_records)
    ingest_items.concat(conflict_result[:ingest_items])

    records.each do |record|
      record.each { |key, value| record[key] = value.scrub("") if value.is_a?(String) }
    end

    return 0 if records.empty?

    ingest_ids = NewsIngestRecorder.record_all(ingest_items)
    records.each { |record| record[:news_ingest_id] = ingest_ids[record[:url]] }
    normalized_ids = NewsNormalizationRecorder.record_all(records)
    records.each do |record|
      ids = normalized_ids[record[:url]]
      next unless ids

      record[:news_source_id] = ids[:news_source_id]
      record[:news_article_id] = ids[:news_article_id]
      record[:content_scope] = ids[:content_scope]
    end
    NewsClaimRecorder.record_all(records)

    assign_clusters(records)
    NewsEvent.upsert_all(records, unique_by: :url)
    record_timeline_events(
      event_type: "news",
      model_class: NewsEvent,
      unique_key: :url,
      unique_values: records.map { |record| record[:url] },
      time_column: :published_at
    )

    Rails.logger.info("NewsRefreshService: #{records.size} total (#{conflict_records.size} from conflict queries)")
    records.size
  rescue StandardError => e
    Rails.logger.error("NewsRefreshService: #{e.message}")
    0
  end

  private

  def fetch_conflict_queries(seen_urls, now)
    records = []
    ingest_items = []

    # Rotate through queries — one per cycle to avoid rate limits
    idx = (Rails.cache.read("gdelt_conflict_query_idx") || 0) % CONFLICT_QUERIES.size
    Rails.cache.write("gdelt_conflict_query_idx", idx + 1)

    # Fetch 2 queries per cycle (current + next) for better coverage
    [idx, (idx + 1) % CONFLICT_QUERIES.size].each do |qi|
      query = CONFLICT_QUERIES[qi]
      query_with_lang = "#{query} sourcelang:eng"
      query_encoded = URI.encode_www_form_component(query_with_lang)
      url = "https://api.gdeltproject.org/api/v2/doc/doc?query=#{query_encoded}&mode=ArtList&maxrecords=50&format=json&timespan=3h"

      begin
        uri = URI(url)
        resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) do |http|
          http.request(Net::HTTP::Get.new(uri))
        end
        next unless resp.is_a?(Net::HTTPSuccess)

        body = resp.body.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        data = JSON.parse(body)
        articles = data["articles"] || []

        articles.each_with_index do |art, article_idx|
          art_url = art["url"]
          ingest_items << {
            item_key: art_url.presence || "gdelt-doc-#{qi}-#{article_idx}",
            source_feed: "gdelt-conflict",
            source_endpoint_url: url,
            external_id: art["socialimage"] || art["sourcecountry"] || art_url,
            raw_url: art_url,
            raw_title: art["title"],
            raw_summary: art["seendate"],
            raw_published_at: art["seendate"],
            fetched_at: now,
            payload_format: "json",
            raw_payload: art,
            http_status: resp.code.to_i,
          }

          next if art_url.blank? || seen_urls.include?(art_url)
          seen_urls.add(art_url)

          title = art["title"]
          next if title.blank?

          # Use GDELT's source country for rough geocoding — AI enrichment will fix later
          published_at = begin
            art["seendate"].present? ? Time.parse(art["seendate"]) : now
          rescue
            now
          end

          adapted = NewsSourceAdapter.normalize!(
            source_adapter: "gdelt_conflict_query",
            attrs: {
              url: art_url,
              title: title,
              summary: art["snippet"] || art["excerpt"],
              name: art["domain"],
              published_at: published_at,
              category: "conflict",
              themes: ["ARMEDCONFLICT"],
              source: "gdelt",
            }
          )

          records << {
            url: adapted[:url],
            name: adapted[:name],
            title: adapted[:title],
            latitude: nil, # geocoded by AI enrichment service
            longitude: nil,
            tone: -3.0, # default negative for conflict queries — enrichment will refine
            level: "elevated",
            category: adapted[:category],
            themes: adapted[:themes],
            published_at: adapted[:published_at],
            fetched_at: now,
            source: "gdelt",
            credibility: "tier2/low",
            created_at: now,
            updated_at: now,
          }
        end
      rescue => e
        Rails.logger.warn("NewsRefreshService conflict query #{qi}: #{e.message}")
      end

      sleep(6) # GDELT rate limit: 1 request per 5 seconds
    end

    { records: records, ingest_items: ingest_items }
  end

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
