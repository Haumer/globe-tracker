require "net/http"
require "zip"
require "nokogiri"
require "digest"

class GeoconfirmedRefreshService
  extend Refreshable

  BASE_URL = "https://geoconfirmed.org/api/map/ExportAsKml".freeze
  USER_AGENT = "GlobeTracker/1.0 (OSINT research platform)".freeze
  RECENT_WINDOW = 90.days
  TWITTER_EPOCH_MS = 1288834974657 # X/Twitter snowflake epoch

  # Regions to ingest — these match GeoConfirmed's map slugs
  REGIONS = %w[
    ukraine
    israel
    iran
    syria
    yemen
    africa
    drc
    world
    afghanistan
    indpak
    myanmar
    nagorno_karabakh
    ven
    pac
    thailandcambodia
    cartel
  ].freeze

  refreshes model: GeoconfirmedEvent, interval: 6.hours, column: :fetched_at

  class << self
    def refresh(regions: REGIONS)
      total = 0
      regions.each do |region|
        count = fetch_region(region)
        total += count
        Rails.logger.info("GeoconfirmedRefreshService: #{region} — #{count} events")
      end
      Rails.logger.info("GeoconfirmedRefreshService: total #{total} events across #{regions.size} regions")
      total
    rescue => e
      Rails.logger.error("GeoconfirmedRefreshService: #{e.class} — #{e.message}")
      0
    end

    private

    def fetch_region(region)
      uri = URI("#{BASE_URL}/#{region}")
      req = Net::HTTP::Get.new(uri)
      req["User-Agent"] = USER_AGENT

      resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 30, read_timeout: 120) do |http|
        http.request(req)
      end

      unless resp.is_a?(Net::HTTPSuccess)
        Rails.logger.error("GeoconfirmedRefreshService: HTTP #{resp.code} for #{region}")
        return 0
      end

      parse_kmz(resp.body, region)
    end

    def parse_kmz(body, region)
      now = Time.current
      records = []
      seen_ids = {}

      Zip::InputStream.open(StringIO.new(body)) do |zis|
        while (entry = zis.get_next_entry)
          next unless entry.name.end_with?(".kml")

          doc = Nokogiri::XML(zis.read)
          doc.remove_namespaces!

          doc.css("Placemark").each_with_index do |placemark, idx|
            record = parse_placemark(placemark, region, now, idx)
            next unless record

            # Deduplicate within batch
            if seen_ids[record[:external_id]]
              record[:external_id] = "#{record[:external_id]}-#{idx}"
            end
            seen_ids[record[:external_id]] = true
            records << record
          end
        end
      end

      return 0 if records.empty?

      # Batch upsert in chunks to avoid oversized queries
      total = 0
      records.each_slice(2000) do |batch|
        GeoconfirmedEvent.upsert_all(batch, unique_by: :external_id)
        total += batch.size
      end
      total
    end

    def parse_placemark(placemark, region, now, index)
      coords_text = placemark.at_css("Point coordinates")&.text&.strip
      return nil if coords_text.blank?

      parts = coords_text.split(",")
      return nil if parts.size < 2

      lng = parts[0].to_f
      lat = parts[1].to_f
      return nil if lat == 0.0 && lng == 0.0

      name = cdata_text(placemark.at_css("name"))
      description = cdata_text(placemark.at_css("description"))
      title = name.presence || extract_title(description)
      style_url = cdata_text(placemark.at_css("styleUrl"))
      icon_key = style_url&.gsub(/^#/, "")&.gsub(/-(?:normal|highlight)$/, "")

      timestamp_el = placemark.at_css("TimeStamp when")
      event_time = parse_time(timestamp_el&.text)

      # Only ingest recent events — skip anything without a timestamp or older than the window
      return nil if event_time.nil?
      return nil if event_time < RECENT_WINDOW.ago

      source_urls, geolocation_urls = extract_urls(description)

      external_id = generate_external_id(region, lat, lng, title, description, index)

      folder_path = extract_folder_path(placemark)

      posted_at = earliest_snowflake_time(source_urls + geolocation_urls)

      {
        external_id: external_id,
        map_region: region,
        folder_path: folder_path,
        title: title&.truncate(500),
        description: description&.truncate(5000),
        latitude: lat,
        longitude: lng,
        event_time: event_time,
        posted_at: posted_at,
        icon_key: icon_key,
        source_urls: source_urls,
        geolocation_urls: geolocation_urls,
        fetched_at: now,
        created_at: now,
        updated_at: now,
      }
    end

    def cdata_text(node)
      return nil if node.nil?

      text = node.children.find { |c| c.cdata? }&.text || node.text
      text&.strip.presence
    end

    def extract_title(description)
      return nil if description.blank?

      # First non-empty line before any link is usually the title
      description.split(/\n|<br\s*\/?>/).each do |line|
        cleaned = line.gsub(/<[^>]+>/, "").strip
        next if cleaned.blank?
        next if cleaned.start_with?("http")
        next if cleaned.start_with?("Source")
        next if cleaned.start_with?("Geolocation")

        return cleaned.truncate(500)
      end
      nil
    end

    def extract_urls(description)
      return [[], []] if description.blank?

      source_urls = []
      geo_urls = []
      current_section = nil

      description.split(/\n|<br\s*\/?>/).each do |line|
        cleaned = line.gsub(/<[^>]+>/, "").strip

        if cleaned =~ /\ASource/i
          current_section = :source
          next
        elsif cleaned =~ /\AGeolocation/i
          current_section = :geo
          next
        end

        urls = cleaned.scan(%r{https?://[^\s<>"]+})
        urls.each do |url|
          case current_section
          when :geo
            geo_urls << url
          else
            source_urls << url
          end
        end
      end

      # Also extract href attributes from <a> tags
      description.scan(/href="([^"]+)"/).flatten.each do |url|
        next unless url.start_with?("http")

        if url.include?("maps.app.goo.gl") || url.include?("google.com/maps") || url.include?("wikimapia")
          geo_urls << url unless geo_urls.include?(url)
        else
          source_urls << url unless source_urls.include?(url)
        end
      end

      [source_urls.uniq.first(10), geo_urls.uniq.first(5)]
    end

    def extract_folder_path(placemark)
      parts = []
      node = placemark.parent
      while node && node.name == "Folder"
        folder_name = cdata_text(node.at_css("> name"))
        parts.unshift(folder_name) if folder_name.present?
        node = node.parent
      end
      parts.join(" / ").presence
    end

    def generate_external_id(region, lat, lng, title, description, index)
      # Stable ID from region + coordinates + first line of content + index for disambiguation
      first_line = (title || description.to_s.split(/\n|<br/).first).to_s.strip.truncate(100)
      fingerprint = Digest::SHA256.hexdigest("#{region}:#{lat.round(6)}:#{lng.round(6)}:#{first_line}")
      "gc-#{region}-#{fingerprint[0..15]}"
    end

    def parse_time(text)
      return nil if text.blank?

      Time.parse(text)
    rescue ArgumentError, TypeError
      nil
    end

    def earliest_snowflake_time(urls)
      times = urls.filter_map { |url| snowflake_time(url) }
      times.min
    end

    def snowflake_time(url)
      return nil unless url.include?("x.com/") || url.include?("twitter.com/")

      status_id = url.match(%r{/status/(\d+)})&.captures&.first&.to_i
      return nil unless status_id && status_id > 1_000_000_000

      timestamp_ms = (status_id >> 22) + TWITTER_EPOCH_MS
      Time.at(timestamp_ms / 1000.0).utc
    rescue
      nil
    end
  end
end
