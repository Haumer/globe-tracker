class HafasTrainService
  # Only keep actual rail services — skip trams, buses, ferries, etc.
  RAIL_CATEGORIES = Set.new(%w[
    ICE TGV RJ RJX NJ EN CJX
    IC EC D
    RE REX RB IR IRE TER R
    S s DBS DRE DRB NRB NRE
    WB
  ]).freeze

  OPERATORS = {
    oebb: {
      url: "https://fahrplan.oebb.at/gate",
      auth: { type: "AID", aid: "5vHavmuWPWIfetEe" },
      client: { id: "OEBB", type: "WEB", name: "webapp", l: "vs_webapp", v: 21901 },
      ext: "OEBB.14",
      ver: "1.88",
      label: "ÖBB",
      flag: "AT",
      # Expanded to cover Central Europe — ÖBB HAFAS shows cross-border trains
      default_rect: { llCrd: { x: 5_000_000, y: 44_000_000 }, urCrd: { x: 19_000_000, y: 56_000_000 } },
    },
  }.freeze

  def self.fetch(bbox: nil, operators: nil)
    new.fetch(bbox: bbox, operators: operators)
  end

  def self.fetch_snapshots(bbox: nil, operators: nil)
    new.fetch_snapshots(bbox: bbox, operators: operators)
  end

  def fetch(bbox: nil, operators: nil)
    fetch_snapshots(bbox: bbox, operators: operators).flat_map { |snapshot| snapshot[:trains] || [] }
  end

  def fetch_snapshots(bbox: nil, operators: nil)
    selected = operators ? OPERATORS.slice(*operators.map(&:to_sym)) : OPERATORS
    threads = selected.map do |key, config|
      Thread.new do
        Thread.current[:results] = fetch_operator_snapshot(key, config, bbox)
      rescue => e
        Rails.logger.warn("HafasTrainService [#{key}]: #{e.message}")
        Thread.current[:results] = failure_snapshot(key, config, bbox: bbox, error_code: e.class.name.demodulize.underscore)
      end
    end

    threads.each { |t| t.join(12) }
    threads.map { |t| t[:results] }.compact
  end

  private

  def fetch_operator_snapshot(key, config, bbox)
    rect = bbox ? bbox_to_rect(bbox) : config[:default_rect]
    fetched_at = Time.current

    uri = URI("#{config[:url]}?rnd=#{(Time.now.to_f * 1000).to_i}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 8
    http.read_timeout = 12

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = build_request_body(config, rect).to_json

    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("HafasTrainService [#{key}]: HTTP #{response.code}")
      return failure_snapshot(
        key,
        config,
        bbox: bbox,
        rect: rect,
        fetched_at: fetched_at,
        raw_payload: { "http_status" => response.code.to_i },
        error_code: "http_#{response.code}"
      )
    end

    data = JSON.parse(response.body)

    {
      operator_key: key.to_s,
      operator_name: config[:label],
      operator_flag: config[:flag],
      request_bbox: bbox,
      request_rect: rect,
      fetched_at: fetched_at,
      raw_payload: data,
      trains: parse_response(data, key, config),
      status: "fetched",
      error_code: nil,
    }
  end

  def bbox_to_rect(bbox)
    south, west, north, east = bbox.split(",").map(&:to_f)
    {
      llCrd: { x: (west * 1_000_000).to_i, y: (south * 1_000_000).to_i },
      urCrd: { x: (east * 1_000_000).to_i, y: (north * 1_000_000).to_i },
    }
  end

  def build_request_body(config, rect)
    {
      id: SecureRandom.hex(8),
      ver: config[:ver],
      lang: "eng",
      auth: config[:auth],
      client: config[:client],
      ext: config[:ext],
      formatted: false,
      svcReqL: [
        {
          meth: "JourneyGeoPos",
          req: { maxJny: 3000, onlyRT: false, rect: rect },
        },
      ],
    }
  end

  def parse_response(data, key, config)
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

      # Whitelist: only keep known rail categories
      next unless RAIL_CATEGORIES.include?(cat_short)

      {
        id: "#{key}-#{Digest::MD5.hexdigest(jny["jid"] || "#{name}-#{idx}")[0, 12]}",
        name: name,
        category: cat_short,
        categoryLong: cat_long,
        operator: config[:label],
        flag: config[:flag],
        lat: pos["y"].to_f / 1_000_000,
        lng: pos["x"].to_f / 1_000_000,
        direction: jny["dirTxt"],
        progress: jny["proc"],
      }
    end
  end

  def failure_snapshot(key, config, bbox:, rect: nil, fetched_at: Time.current, raw_payload: {}, error_code:)
    {
      operator_key: key.to_s,
      operator_name: config[:label],
      operator_flag: config[:flag],
      request_bbox: bbox,
      request_rect: rect,
      fetched_at: fetched_at,
      raw_payload: raw_payload,
      trains: [],
      status: "failed",
      error_code: error_code,
    }
  end
end
