class CommoditySiteCatalog
  DATA_FILE = Rails.root.join("db", "data", "commodity_sites.json").freeze

  class << self
    def all
      return [] unless File.exist?(DATA_FILE)

      JSON.parse(File.read(DATA_FILE))
    rescue JSON::ParserError => error
      Rails.logger.error("CommoditySiteCatalog parse failed: #{error.message}")
      []
    end

    def last_modified
      File.exist?(DATA_FILE) ? File.mtime(DATA_FILE) : nil
    end

    def etag
      return "commodity-sites:missing" unless File.exist?(DATA_FILE)

      stat = File.stat(DATA_FILE)
      "commodity-sites:#{stat.size}:#{stat.mtime.to_i}"
    end
  end
end
