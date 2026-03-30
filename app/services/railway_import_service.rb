class RailwayImportService
  SOURCE_URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_railroads.geojson"

  def self.import!
    Rails.logger.info "[RailwayImport] Downloading Natural Earth railroads..."
    response = Net::HTTP.get(URI(SOURCE_URL))
    data = JSON.parse(response)

    features = data["features"]
    Rails.logger.info "[RailwayImport] Processing #{features.size} features..."

    records = []
    features.each do |feat|
      coords = feat.dig("geometry", "coordinates")
      next if coords.nil? || coords.size < 2

      props = feat["properties"] || {}

      # Preserve source precision so train snapping can align to the imported rail geometry.
      simplified = coords.map { |c| [c[0].to_f, c[1].to_f] }
      simplified = simplified.chunk_while { |a, b| a == b }.map(&:first)
      next if simplified.size < 2

      lats = simplified.map { |c| c[1] }
      lngs = simplified.map { |c| c[0] }

      records << {
        category: props["category"].to_i,
        electrified: props["electric"].to_i,
        continent: props["continent"].to_s,
        min_lat: lats.min,
        max_lat: lats.max,
        min_lng: lngs.min,
        max_lng: lngs.max,
        coordinates: simplified,
        created_at: Time.current,
        updated_at: Time.current,
      }
    end

    Railway.delete_all
    Railway.insert_all(records)
    Rails.logger.info "[RailwayImport] Imported #{records.size} railway segments"
    records.size
  end
end
