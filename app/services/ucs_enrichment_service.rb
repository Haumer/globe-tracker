require "csv"
require "net/http"

class UcsEnrichmentService
  UCS_URL = "https://www.ucs.org/media/11493" # Tab-delimited text

  class << self
    def enrich(force: false)
      cache_path = Rails.root.join("tmp", "ucs_satellites.txt")

      # Download if not cached or forced
      if force || !File.exist?(cache_path) || File.mtime(cache_path) < 30.days.ago
        download(cache_path)
      end

      import(cache_path)
    end

    private

    def download(path)
      Rails.logger.info("UCS: Downloading satellite database...")
      uri = URI(UCS_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 60
      response = http.request(Net::HTTP::Get.new(uri))

      if response.is_a?(Net::HTTPSuccess)
        File.write(path, response.body)
        Rails.logger.info("UCS: Downloaded #{response.body.bytesize} bytes")
      else
        Rails.logger.error("UCS: Download failed (#{response.code})")
      end
    end

    def import(path)
      return 0 unless File.exist?(path)

      rows = CSV.read(path, col_sep: "\t", encoding: "ISO-8859-1:UTF-8", headers: true)

      # Build lookup by NORAD number
      enrichments = {}
      rows.each do |row|
        norad = row["NORAD Number"]&.strip&.to_i
        next if norad.nil? || norad == 0

        enrichments[norad] = {
          country_owner: row["Country of Operator/Owner"]&.strip&.truncate(100),
          users: row["Users"]&.strip&.truncate(100),
          purpose: row["Purpose"]&.strip&.truncate(100),
          detailed_purpose: row["Detailed Purpose"]&.strip&.truncate(200),
          orbit_class: row["Class of Orbit"]&.strip&.truncate(50),
          launch_date: row["Date of Launch"]&.strip&.truncate(20),
          launch_site: row["Launch Site"]&.strip&.truncate(100),
          launch_vehicle: row["Launch Vehicle"]&.strip&.truncate(100),
          contractor: row["Contractor"]&.strip&.truncate(200),
          expected_lifetime: row["Expected Lifetime (yrs.)"]&.strip&.truncate(20),
        }
      end

      Rails.logger.info("UCS: Parsed #{enrichments.size} satellites, matching against DB...")

      # Batch update in chunks
      updated = 0
      our_norad_ids = Satellite.pluck(:norad_id)
      matched_ids = our_norad_ids & enrichments.keys

      matched_ids.each_slice(500) do |batch|
        batch.each do |norad_id|
          data = enrichments[norad_id]
          Satellite.where(norad_id: norad_id).update_all(data)
          updated += 1
        end
      end

      Rails.logger.info("UCS: Enriched #{updated} of #{our_norad_ids.size} satellites (#{enrichments.size} in UCS DB)")
      updated
    end
  end
end
