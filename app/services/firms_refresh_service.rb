require "csv"

class FirmsRefreshService
  extend HttpClient
  extend Refreshable
  include TimelineRecorder
  include RefreshableDataService

  SOURCES = {
    "VIIRS_SNPP_NRT" => "Suomi NPP",
    "VIIRS_NOAA20_NRT" => "NOAA-20",
    "VIIRS_NOAA21_NRT" => "NOAA-21",
    "MODIS_NRT" => nil,
  }.freeze

  refreshes model: FireHotspot, interval: 15.minutes

  private

  def fetch_data
    map_key = ENV["FIRMS_MAP_KEY"]
    return nil unless map_key.present?

    # Return the map_key as the "data" — parse_records handles fetching per-source
    map_key
  end

  def parse_records(data)
    map_key = data
    now = Time.current
    all_records = []

    SOURCES.each_key do |source|
      records = fetch_source(source, map_key, now)
      all_records.concat(records)
    end

    all_records
  end

  def upsert_records(records)
    FireHotspot.upsert_all(records, unique_by: :external_id)
  end

  def after_upsert(records)
    FireHotspot.where("acq_datetime < ?", 72.hours.ago).delete_all
  end

  def timeline_config
    { event_type: "fire", model_class: FireHotspot, time_column: :acq_datetime }
  end

  def fetch_source(source, map_key, now)
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

      satellite = default_satellite || normalize_satellite(row["satellite"])
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

  def normalize_satellite(name)
    case name&.strip
    when /terra/i then "Terra"
    when /aqua/i then "Aqua"
    else name&.strip
    end
  end

  def parse_acq_time(date_str, time_str)
    return nil unless date_str.present?
    time_str = time_str.to_s.rjust(4, "0")
    Time.parse("#{date_str} #{time_str[0..1]}:#{time_str[2..3]} UTC")
  rescue
    nil
  end
end
