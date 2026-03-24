class MilitaryBaseRefreshService
  extend HttpClient
  extend Refreshable

  OVERPASS_URL = "https://overpass-api.de/api/interpreter".freeze

  # Conflict-zone bounding boxes: [south, west, north, east]
  REGION_BBOXES = {
    middle_east:   [12, 25, 42, 65],
    ukraine_russia: [44, 22, 56, 45],
    east_asia:     [20, 100, 45, 145],
    horn_of_africa: [-5, 30, 20, 55],
  }.freeze

  refreshes model: MilitaryBase, interval: 7.days

  def refresh
    now = Time.current
    count = 0

    count += load_hardcoded_bases(now)
    count += fetch_overpass_data(now)

    Rails.logger.info("MilitaryBaseRefreshService: total #{count} bases")
    count
  rescue StandardError => e
    Rails.logger.error("MilitaryBaseRefreshService: #{e.message}")
    0
  end

  private

  def fetch_overpass_data(now)
    total = 0

    REGION_BBOXES.each do |region, bbox|
      south, west, north, east = bbox
      # Only fetch active installation types — exclude bunker, trench, ruins
      query = <<~OQL
        [out:json][timeout:120][bbox:#{south},#{west},#{north},#{east}];
        (
          node["military"~"barracks|base|airfield|naval_base|range|training_area|office|checkpoint"];
          way["military"~"barracks|base|airfield|naval_base|range|training_area|office|checkpoint"];
          relation["military"~"barracks|base|airfield|naval_base|range|training_area|office|checkpoint"];
        );
        out center body;
      OQL

      data = self.class.http_post(
        URI(OVERPASS_URL),
        form_data: { data: query },
        open_timeout: 15,
        read_timeout: 130,
        retries: 1,
        retry_delay: 5,
      )

      next unless data && data["elements"]

      records = data["elements"].filter_map { |el| parse_element(el, now) }
      next if records.empty?

      records.each_slice(500) do |batch|
        MilitaryBase.upsert_all(batch, unique_by: :external_id)
      end

      total += records.size
      Rails.logger.info("MilitaryBaseRefreshService: #{region} yielded #{records.size} bases")

      # Be polite to Overpass API
      sleep(5)
    end

    total
  end

  def parse_element(el, now)
    tags = el["tags"] || {}
    lat = el["lat"] || el.dig("center", "lat")
    lon = el["lon"] || el.dig("center", "lon")
    return nil if lat.nil? || lon.nil?

    type_tag = tags["military"] || "other"
    base_type = normalize_type(type_tag)

    element_type = el["type"] # node, way, relation
    external_id = "osm-#{element_type}-#{el["id"]}"

    {
      external_id: external_id,
      name: tags["name"] || tags["name:en"],
      base_type: base_type,
      country: tags["addr:country"],
      operator: tags["operator"],
      latitude: lat.to_f,
      longitude: lon.to_f,
      source: "osm",
      metadata: {
        military_tag: type_tag,
        landuse: tags["landuse"],
        description: tags["description"],
      }.compact,
      fetched_at: now,
      created_at: now,
      updated_at: now,
    }
  end

  def normalize_type(tag)
    case tag.to_s.downcase
    when "barracks", "garrison", "base", "camp"
      "army"
    when "naval_base", "naval_station", "port"
      "navy"
    when "airfield", "air_base", "airstrip"
      "air_force"
    when "nuclear_explosion_site", "nuclear"
      "nuclear"
    when "missile_site", "missile", "launchpad"
      "missile"
    when "training_area", "range", "training", "exercise_area"
      "training"
    when "depot", "ammunition", "storage", "bunker", "office", "checkpoint"
      "logistics"
    else
      "other"
    end
  end

  def load_hardcoded_bases(now)
    bases = hardcoded_bases.map do |b|
      {
        external_id: b[:external_id],
        name: b[:name],
        base_type: b[:base_type],
        country: b[:country],
        operator: b[:operator],
        latitude: b[:latitude],
        longitude: b[:longitude],
        source: "manual",
        metadata: {},
        fetched_at: now,
        created_at: now,
        updated_at: now,
      }
    end

    return 0 if bases.empty?
    MilitaryBase.upsert_all(bases, unique_by: :external_id)
    bases.size
  end

  def hardcoded_bases
    [
      # US Overseas Bases
      { external_id: "manual-ramstein", name: "Ramstein Air Base", base_type: "air_force", country: "DE", operator: "US Air Force", latitude: 49.4369, longitude: 7.6003 },
      { external_id: "manual-incirlik", name: "Incirlik Air Base", base_type: "air_force", country: "TR", operator: "US Air Force", latitude: 37.0021, longitude: 35.4259 },
      { external_id: "manual-al-udeid", name: "Al Udeid Air Base", base_type: "air_force", country: "QA", operator: "US Air Force", latitude: 25.1174, longitude: 51.3150 },
      { external_id: "manual-diego-garcia", name: "Naval Support Facility Diego Garcia", base_type: "navy", country: "IO", operator: "US Navy", latitude: -7.3133, longitude: 72.4111 },
      { external_id: "manual-camp-humphreys", name: "Camp Humphreys", base_type: "army", country: "KR", operator: "US Army", latitude: 36.9627, longitude: 127.0313 },
      { external_id: "manual-yokosuka", name: "Naval Base Yokosuka", base_type: "navy", country: "JP", operator: "US Navy", latitude: 35.2836, longitude: 139.6650 },
      { external_id: "manual-kadena", name: "Kadena Air Base", base_type: "air_force", country: "JP", operator: "US Air Force", latitude: 26.3516, longitude: 127.7692 },
      { external_id: "manual-guantanamo", name: "Naval Station Guantanamo Bay", base_type: "navy", country: "CU", operator: "US Navy", latitude: 19.9023, longitude: -75.0961 },
      { external_id: "manual-bahrain", name: "NSA Bahrain", base_type: "navy", country: "BH", operator: "US Navy", latitude: 26.2361, longitude: 50.6517 },
      { external_id: "manual-djibouti", name: "Camp Lemonnier", base_type: "army", country: "DJ", operator: "US Military", latitude: 11.5472, longitude: 43.1542 },
      { external_id: "manual-thule", name: "Pituffik Space Base", base_type: "air_force", country: "GL", operator: "US Space Force", latitude: 76.5312, longitude: -68.7032 },
      { external_id: "manual-rota", name: "Naval Station Rota", base_type: "navy", country: "ES", operator: "US Navy", latitude: 36.6391, longitude: -6.3496 },
      { external_id: "manual-sigonella", name: "NAS Sigonella", base_type: "air_force", country: "IT", operator: "US Navy", latitude: 37.4017, longitude: 14.9222 },
      { external_id: "manual-aviano", name: "Aviano Air Base", base_type: "air_force", country: "IT", operator: "US Air Force", latitude: 46.0319, longitude: 12.5965 },
      { external_id: "manual-iwakuni", name: "MCAS Iwakuni", base_type: "air_force", country: "JP", operator: "US Marines", latitude: 34.1464, longitude: 132.2356 },

      # Russian Key Bases
      { external_id: "manual-kaliningrad", name: "Kaliningrad Naval Base", base_type: "navy", country: "RU", operator: "Russian Navy", latitude: 54.7104, longitude: 20.5100 },
      { external_id: "manual-sevastopol", name: "Sevastopol Naval Base", base_type: "navy", country: "UA", operator: "Russian Navy", latitude: 44.6167, longitude: 33.5254 },
      { external_id: "manual-tartus", name: "Tartus Naval Facility", base_type: "navy", country: "SY", operator: "Russian Navy", latitude: 34.8890, longitude: 35.8866 },
      { external_id: "manual-hmeimim", name: "Hmeimim Air Base", base_type: "air_force", country: "SY", operator: "Russian Air Force", latitude: 35.4081, longitude: 35.9486 },
      { external_id: "manual-engels", name: "Engels Air Base", base_type: "nuclear", country: "RU", operator: "Russian Air Force", latitude: 51.4830, longitude: 46.2010 },
      { external_id: "manual-plesetsk", name: "Plesetsk Cosmodrome", base_type: "missile", country: "RU", operator: "Russian Space Forces", latitude: 62.9271, longitude: 40.5778 },
      { external_id: "manual-murmansk", name: "Severomorsk Naval Base", base_type: "navy", country: "RU", operator: "Russian Navy", latitude: 69.0733, longitude: 33.4178 },
      { external_id: "manual-vladivostok", name: "Vladivostok Naval Base", base_type: "navy", country: "RU", operator: "Russian Navy", latitude: 43.1056, longitude: 131.8735 },

      # Chinese Key Bases
      { external_id: "manual-yulin", name: "Yulin Naval Base", base_type: "navy", country: "CN", operator: "PLA Navy", latitude: 18.2276, longitude: 109.5542 },
      { external_id: "manual-djibouti-cn", name: "PLA Support Base Djibouti", base_type: "navy", country: "DJ", operator: "PLA Navy", latitude: 11.5917, longitude: 43.0800 },
      { external_id: "manual-fiery-cross", name: "Fiery Cross Reef Base", base_type: "air_force", country: "CN", operator: "PLA", latitude: 9.5500, longitude: 112.8833 },
      { external_id: "manual-mischief-reef", name: "Mischief Reef Base", base_type: "navy", country: "CN", operator: "PLA Navy", latitude: 9.9000, longitude: 115.5333 },
      { external_id: "manual-subi-reef", name: "Subi Reef Base", base_type: "air_force", country: "CN", operator: "PLA", latitude: 10.9200, longitude: 114.0833 },
      { external_id: "manual-zhanjiang", name: "Zhanjiang Naval Base", base_type: "navy", country: "CN", operator: "PLA Navy", latitude: 21.2000, longitude: 110.4000 },

      # Iranian Key Bases
      { external_id: "manual-bandar-abbas", name: "Bandar Abbas Naval Base", base_type: "navy", country: "IR", operator: "IRIN", latitude: 27.1832, longitude: 56.2764 },
      { external_id: "manual-bushehr", name: "Bushehr Air Base", base_type: "air_force", country: "IR", operator: "IRIAF", latitude: 28.9485, longitude: 50.8346 },
      { external_id: "manual-isfahan", name: "Isfahan Nuclear Facility", base_type: "nuclear", country: "IR", operator: "AEOI", latitude: 32.6500, longitude: 51.6833 },
      { external_id: "manual-natanz", name: "Natanz Enrichment Facility", base_type: "nuclear", country: "IR", operator: "AEOI", latitude: 33.7250, longitude: 51.7272 },
      { external_id: "manual-fordow", name: "Fordow Enrichment Facility", base_type: "nuclear", country: "IR", operator: "AEOI", latitude: 34.8833, longitude: 51.5833 },
      { external_id: "manual-chabahar", name: "Chabahar Naval Base", base_type: "navy", country: "IR", operator: "IRIN", latitude: 25.2919, longitude: 60.6525 },

      # NATO / Other Key Bases
      { external_id: "manual-norfolk", name: "Naval Station Norfolk", base_type: "navy", country: "US", operator: "US Navy", latitude: 36.9460, longitude: -76.3035 },
      { external_id: "manual-pearl-harbor", name: "Joint Base Pearl Harbor-Hickam", base_type: "navy", country: "US", operator: "US Navy", latitude: 21.3469, longitude: -157.9431 },
      { external_id: "manual-raf-lakenheath", name: "RAF Lakenheath", base_type: "air_force", country: "GB", operator: "US Air Force", latitude: 52.4093, longitude: 0.5608 },
      { external_id: "manual-faslane", name: "HMNB Clyde (Faslane)", base_type: "nuclear", country: "GB", operator: "Royal Navy", latitude: 56.0667, longitude: -4.8167 },
      { external_id: "manual-changi", name: "Changi Naval Base", base_type: "navy", country: "SG", operator: "Republic of Singapore Navy", latitude: 1.3269, longitude: 104.0000 },

      # North Korea
      { external_id: "manual-yongbyon", name: "Yongbyon Nuclear Complex", base_type: "nuclear", country: "KP", operator: "DPRK", latitude: 39.7958, longitude: 125.7553 },
      { external_id: "manual-sohae", name: "Sohae Satellite Launching Station", base_type: "missile", country: "KP", operator: "DPRK", latitude: 39.6600, longitude: 124.7053 },
      { external_id: "manual-punggye-ri", name: "Punggye-ri Nuclear Test Site", base_type: "nuclear", country: "KP", operator: "DPRK", latitude: 41.2772, longitude: 129.0836 },

      # India / Pakistan
      { external_id: "manual-karwar", name: "INS Kadamba (Karwar)", base_type: "navy", country: "IN", operator: "Indian Navy", latitude: 14.8050, longitude: 74.1138 },
      { external_id: "manual-visakhapatnam", name: "INS Visakhapatnam Naval Base", base_type: "navy", country: "IN", operator: "Indian Navy", latitude: 17.7000, longitude: 83.3000 },
      { external_id: "manual-kahuta", name: "Khan Research Laboratories (Kahuta)", base_type: "nuclear", country: "PK", operator: "Pakistan AEC", latitude: 33.5833, longitude: 73.3667 },
    ]
  end
end
