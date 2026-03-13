require "csv"

class FirmsRefreshService
  extend HttpClient
  include TimelineRecorder

  # FIRMS API sources → satellite name mapping
  SOURCES = {
    "VIIRS_SNPP_NRT" => "Suomi NPP",
    "VIIRS_NOAA20_NRT" => "NOAA-20",
    "VIIRS_NOAA21_NRT" => "NOAA-21",
    "MODIS_NRT" => nil, # satellite comes from data itself (Terra/Aqua)
  }.freeze

  REFRESH_INTERVAL = 15.minutes

  class << self
    def refresh_if_stale(force: false)
      return 0 if !force && !stale?
      new.refresh
    end

    def stale?
      latest_fetch_at.blank? || latest_fetch_at < REFRESH_INTERVAL.ago
    end

    def latest_fetch_at
      FireHotspot.maximum(:fetched_at)
    end
  end

  def refresh
    map_key = ENV["FIRMS_MAP_KEY"]
    return 0 unless map_key.present?

    now = Time.current
    all_records = []

    SOURCES.each_key do |source|
      records = fetch_source(source, map_key, now)
      all_records.concat(records)
    end

    return 0 if all_records.empty?

    FireHotspot.upsert_all(all_records, unique_by: :external_id)

    # Clean old data (>72h)
    FireHotspot.where("acq_datetime < ?", 72.hours.ago).delete_all

    record_timeline_events(
      event_type: "fire",
      model_class: FireHotspot,
      unique_key: :external_id,
      unique_values: all_records.map { |r| r[:external_id] },
      time_column: :acq_datetime
    )

    all_records.size
  rescue StandardError => e
    Rails.logger.error("FirmsRefreshService: #{e.message}")
    0
  end

  private

  def fetch_source(source, map_key, now)
    # FIRMS CSV endpoint: world, last 24h
    uri = URI("https://firms.modaps.eosdis.nasa.gov/api/area/csv/#{map_key}/#{source}/world/1")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 60

    response = http.request(Net::HTTP::Get.new(uri))
    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("FirmsRefreshService: #{source} HTTP #{response.code}")
      return []
    end

    default_satellite = SOURCES[source]
    instrument = source.start_with?("MODIS") ? "MODIS" : "VIIRS"
    records = []

    CSV.parse(response.body, headers: true) do |row|
      lat = row["latitude"]&.to_f
      lng = row["longitude"]&.to_f
      next if lat.nil? || lng.nil? || lat == 0.0 && lng == 0.0

      acq_date = row["acq_date"]
      acq_time = row["acq_time"]
      acq_datetime = parse_acq_time(acq_date, acq_time)

      satellite = default_satellite || row["satellite"]&.strip
      # Normalize satellite names from MODIS data
      satellite = case satellite
                  when /terra/i then "Terra"
                  when /aqua/i then "Aqua"
                  else satellite
                  end

      external_id = "#{satellite}_#{lat}_#{lng}_#{acq_date}_#{acq_time}"

      records << {
        external_id: external_id,
        latitude: lat,
        longitude: lng,
        brightness: row["bright_ti4"]&.to_f || row["brightness"]&.to_f,
        confidence: row["confidence"]&.strip,
        satellite: satellite,
        instrument: instrument,
        frp: row["frp"]&.to_f,
        bright_t31: row["bright_ti5"]&.to_f || row["bright_t31"]&.to_f,
        daynight: row["daynight"]&.strip,
        acq_datetime: acq_datetime,
        fetched_at: now,
        created_at: now,
        updated_at: now,
      }
    end

    Rails.logger.info("FirmsRefreshService: #{source} → #{records.size} hotspots")
    records
  rescue StandardError => e
    Rails.logger.error("FirmsRefreshService fetch #{source}: #{e.message}")
    []
  end

  def parse_acq_time(date_str, time_str)
    return nil unless date_str.present?
    # acq_date: "2024-01-15", acq_time: "0354" (HHMM)
    time_str = time_str.to_s.rjust(4, "0")
    Time.parse("#{date_str} #{time_str[0..1]}:#{time_str[2..3]} UTC")
  rescue
    nil
  end
end
