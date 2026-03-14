class OebbTrainService
  HAFAS_URL = "https://fahrplan.oebb.at/gate"

  def self.fetch(bbox: nil)
    new.fetch(bbox: bbox)
  end

  def fetch(bbox: nil)
    rect = bbox ? bbox_to_rect(bbox) : default_rect

    uri = URI("#{HAFAS_URL}?rnd=#{(Time.now.to_f * 1000).to_i}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 15

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = build_request_body(rect).to_json

    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("OebbTrainService: HTTP #{response.code}")
      return []
    end

    parse_response(JSON.parse(response.body))
  rescue StandardError => e
    Rails.logger.error("OebbTrainService: #{e.message}")
    []
  end

  private

  def default_rect
    { llCrd: { x: 9_500_000, y: 46_500_000 }, urCrd: { x: 17_100_000, y: 49_000_000 } }
  end

  def bbox_to_rect(bbox)
    south, west, north, east = bbox.split(",").map(&:to_f)
    {
      llCrd: { x: (west * 1_000_000).to_i, y: (south * 1_000_000).to_i },
      urCrd: { x: (east * 1_000_000).to_i, y: (north * 1_000_000).to_i },
    }
  end

  def build_request_body(rect)
    {
      id: "2hg4aqaekeqmww4s",
      ver: "1.88",
      lang: "deu",
      auth: { type: "AID", aid: "5vHavmuWPWIfetEe" },
      client: { id: "OEBB", type: "WEB", name: "webapp", l: "vs_webapp", v: 21901 },
      ext: "OEBB.14",
      formatted: false,
      svcReqL: [
        {
          meth: "JourneyGeoPos",
          req: { maxJny: 1000, onlyRT: true, rect: rect },
        },
      ],
    }
  end

  def parse_response(data)
    svc = data.dig("svcResL", 0, "res")
    return [] unless svc

    journeys = svc["jnyL"] || []
    products = svc.dig("common", "prodL") || []

    journeys.each_with_index.filter_map do |jny, idx|
      pos = jny["pos"]
      next unless pos && pos["x"] && pos["y"]

      prod = products[jny["prodX"]] if jny["prodX"]

      name = prod&.dig("name")&.strip || "Train"
      cat_short = prod&.dig("prodCtx", "catOutS")&.strip || ""
      cat_long = prod&.dig("prodCtx", "catOutL")&.strip || cat_short

      # Skip buses — only keep rail services
      next if cat_short.downcase.in?(%w[bus]) || cat_long.downcase.include?("bus")

      {
        id: "#{idx}-#{Digest::MD5.hexdigest(jny["jid"] || "#{name}-#{pos['x']}-#{pos['y']}")[0, 8]}",
        name: name,
        category: cat_short,
        categoryLong: cat_long,
        lat: pos["y"].to_f / 1_000_000,
        lng: pos["x"].to_f / 1_000_000,
        direction: jny["dirTxt"],
        progress: jny["proc"],
      }
    end
  end
end
