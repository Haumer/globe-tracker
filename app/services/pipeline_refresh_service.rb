require "open-uri"
require "zip"

class PipelineRefreshService
  extend HttpClient
  extend Refreshable

  REPO_ZIP_URL = "https://github.com/GlobalEnergyMonitor/GOIT-GGIT-pipeline-routes/archive/refs/heads/main.zip".freeze
  SEED_FILE = Rails.root.join("db", "data", "pipelines.json").freeze
  CACHE_DIR = Rails.root.join("tmp", "gem_pipelines").freeze

  # Minimum length in km to include (filters out small gathering lines)
  MIN_LENGTH_KM = 50

  refreshes model: Pipeline, interval: 30.days

  def refresh
    now = Time.current
    count = 0

    # First load curated seed data (always)
    count += load_seed_data(now)

    # Then fetch GEM data
    count += fetch_gem_data(now)

    count
  rescue StandardError => e
    Rails.logger.error("PipelineRefreshService: #{e.message}")
    0
  end

  private

  def load_seed_data(now)
    return 0 unless File.exist?(SEED_FILE)

    data = JSON.parse(File.read(SEED_FILE))
    records = data.filter_map do |entry|
      next if entry["id"].blank? || entry["coordinates"].blank?

      {
        pipeline_id: entry["id"],
        name: entry["name"],
        pipeline_type: entry["type"],
        status: entry["status"] || "operational",
        length_km: entry["length_km"],
        coordinates: entry["coordinates"],
        color: entry["color"] || color_for_type(entry["type"]),
        country: entry["country"],
        fetched_at: now,
        created_at: now,
        updated_at: now,
      }
    end

    return 0 if records.empty?
    Pipeline.upsert_all(records, unique_by: :pipeline_id)
    records.size
  end

  def fetch_gem_data(now)
    FileUtils.mkdir_p(CACHE_DIR)
    zip_path = CACHE_DIR.join("gem_pipelines.zip")

    # Download ZIP (skip if recently downloaded)
    if !File.exist?(zip_path) || File.mtime(zip_path) < 7.days.ago
      Rails.logger.info("PipelineRefreshService: downloading GEM pipeline data...")
      download_file(REPO_ZIP_URL, zip_path)
    end

    return 0 unless File.exist?(zip_path)

    records = []
    Zip::File.open(zip_path.to_s) do |zip|
      zip.each do |entry|
        next unless entry.name.end_with?(".geojson")
        next unless entry.name.include?("individual-routes/")

        pipeline_type = if entry.name.include?("gas-pipelines")
          "gas"
        elsif entry.name.include?("liquid-pipelines")
          "oil"
        elsif entry.name.include?("hydrogen-pipelines")
          "hydrogen"
        else
          next
        end

        begin
          geojson = JSON.parse(entry.get_input_stream.read)
          features = geojson["features"] || []
          next if features.empty?

          feature = features.first
          props = feature["properties"] || {}
          geom = feature["geometry"] || {}
          coords = geom["coordinates"] || []
          next if coords.empty?

          name = props["name"] || props["Name"] || ""
          next if name.blank?

          # Extract project ID from filename
          project_id = File.basename(entry.name, ".geojson")

          # Skip if already covered by seed data
          next if seed_ids.include?(project_id)

          # Calculate approximate length from coordinates
          length_km = props["Length"]&.to_f
          total_points = count_points(coords)

          # Filter: skip short pipelines and those with very few points
          if length_km && length_km < MIN_LENGTH_KM
            next
          elsif !length_km && total_points < 10
            next
          end

          # Flatten MultiLineString to array of [lat, lng] segments for our format
          flat_coords = flatten_multilinestring(coords)
          next if flat_coords.length < 2

          status = map_status(props["State"] || props["status"])

          records << {
            pipeline_id: "gem-#{project_id}",
            name: name,
            pipeline_type: pipeline_type,
            status: status,
            length_km: length_km,
            coordinates: flat_coords,
            color: color_for_type(pipeline_type),
            country: extract_country(props),
            fetched_at: now,
            created_at: now,
            updated_at: now,
          }
        rescue JSON::ParserError
          next
        end
      end
    end

    return 0 if records.empty?

    # Batch upsert in chunks
    records.each_slice(500) do |batch|
      Pipeline.upsert_all(batch, unique_by: :pipeline_id)
    end

    Rails.logger.info("PipelineRefreshService: imported #{records.size} GEM pipelines")
    records.size
  end

  def download_file(url, path)
    uri = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 120) do |http|
      request = Net::HTTP::Get.new(uri)
      http.request(request)
    end

    # Follow redirect
    if response.is_a?(Net::HTTPRedirection)
      redirect_uri = URI(response["location"])
      response = Net::HTTP.start(redirect_uri.host, redirect_uri.port, use_ssl: true, open_timeout: 15, read_timeout: 120) do |http|
        http.request(Net::HTTP::Get.new(redirect_uri))
      end
    end

    if response.is_a?(Net::HTTPSuccess)
      File.binwrite(path.to_s, response.body)
    else
      Rails.logger.error("PipelineRefreshService: download failed with #{response.code}")
    end
  end

  def flatten_multilinestring(coords)
    # coords is array of line segments, each segment is array of [lng, lat] points
    # Convert to our format: array of [lat, lng] points
    result = []
    coords.each do |segment|
      next unless segment.is_a?(Array)
      segment.each do |point|
        next unless point.is_a?(Array) && point.length >= 2
        result << [point[1].to_f, point[0].to_f] # [lat, lng]
      end
    end
    result
  end

  def count_points(coords)
    coords.sum { |seg| seg.is_a?(Array) ? seg.length : 0 }
  end

  def map_status(state)
    return "operational" if state.blank?
    case state.to_s.downcase
    when /operat|active/ then "operational"
    when /construct|develop/ then "under_construction"
    when /propos|permit|plan/ then "proposed"
    when /shelv|cancel|retired|mothball|idle/ then "inactive"
    else "operational"
    end
  end

  def extract_country(props)
    props["Country"] || props["State"] || ""
  end

  def color_for_type(type)
    case type
    when "oil" then "#ff6d00"
    when "gas" then "#76ff03"
    when "hydrogen" then "#00b0ff"
    when "products" then "#ffab00"
    else "#ff6d00"
    end
  end

  def seed_ids
    @seed_ids ||= begin
      return Set.new unless File.exist?(SEED_FILE)
      data = JSON.parse(File.read(SEED_FILE))
      Set.new(data.map { |e| e["id"] })
    end
  end
end
