# The most precise boundary that contains a coordinate. The board uses it to
# draw a real shape where it would otherwise guess with a circle, and the
# layer planner uses it to recover a country code for the many registry
# entities that never got one (59 of 63 live situations at last count).
#
# Precision is a ladder, finest rung that answers wins:
#
#   district -- the app's own curated files (DE/AT/CH today), else
#               geoBoundaries ADM2 for the anchor's country
#   region   -- the Natural Earth admin-1 set the boundary layer already
#               fetches and caches
#
# Admin-1 is resolved first regardless, because its feature names the country
# that scopes the district lookup. Each anchor's answer -- including "nothing
# contains it", which is normal for sea anchors like a strait -- is cached on
# its rounded coordinate, so the expensive path runs once per anchor per TTL,
# and WarmSituationLayersJob pays it after each build rather than a request.
class AnchorRegionService
  CACHE_TTL = 12.hours

  NONE = "none".freeze

  class << self
    # anchors: [{ id:, lat:, lng: }] -> { id => compact GeoJSON feature }.
    # Anchors no region contains are simply absent from the result.
    def features_for(anchors)
      result = {}
      missing = []

      anchors.each do |anchor|
        next if anchor[:lat].nil? || anchor[:lng].nil?

        cached = Rails.cache.read(cache_key(anchor[:lat], anchor[:lng]))
        case cached
        when NONE then next
        when Hash then result[anchor[:id]] = cached
        else missing << anchor
        end
      end

      resolve(missing).each { |id, feature| result[id] = feature if feature }
      result
    end

    def country_code_for(lat:, lng:)
      features_for([ { id: :probe, lat: lat, lng: lng } ])
        .dig(:probe, "properties", "country_code")
    end

    private

    def resolve(anchors)
      return {} if anchors.empty?

      Rails.logger.info("[AnchorRegionService] resolving #{anchors.size} uncached anchors")
      admin1 = index_features(admin1_features)
      return {} if admin1.empty?

      district_indexes = {}
      anchors.each_with_object({}) do |anchor, out|
        lat = anchor[:lat].to_f
        lng = anchor[:lng].to_f

        region = containing_feature(admin1, lat, lng)
        unless region
          Rails.cache.write(cache_key(anchor[:lat], anchor[:lng]), NONE, expires_in: CACHE_TTL)
          next
        end

        properties = region.fetch("properties", {})
        country = country_code(properties)
        districts = (district_indexes[country] ||= index_features(district_features(properties)))
        district = containing_feature(districts, lat, lng)

        # "More precise" means smaller, not "from the district dataset":
        # geoBoundaries' ADM2 for Italy is its regions while Natural Earth's
        # admin-1 is its provinces, and blindly preferring the district rung
        # would swap Cuneo for the whole of Piemonte.
        district = nil if district && approx_area(district) > approx_area(region)

        compact = district ? compact_district(district, country) : compact_region(region, country)
        Rails.cache.write(cache_key(anchor[:lat], anchor[:lng]), compact, expires_in: CACHE_TTL)
        out[anchor[:id]] = compact
      end
    end

    # Read-through on purpose: http_get's cache_key is a *fallback* cache --
    # it downloads first and reads the cache only on failure -- so without
    # this layer every resolve re-downloaded the 25MB admin-1 set. Prod paid
    # ~30s per /regions request until this was learned the hard way.
    def admin1_features
      Rails.cache.fetch("anchor-region:admin1:v1", expires_in: 12.hours) do
        dataset = GeographyBoundaryService.fetch("admin1")
        dataset.is_a?(Hash) ? Array(dataset["features"]) : []
      end
    end

    # The app's own district files are authoritative where they exist; the
    # global ADM2 set covers everywhere else. Cached per country including
    # the empty answer: geoBoundaries has no ADM2 release for some countries
    # (and Natural Earth writes codes like PSX it has never heard of), and
    # re-asking is a guaranteed 404 per request until the circuit opens.
    def district_features(admin1_properties)
      iso2 = admin1_properties["iso_a2"].to_s.strip.upcase
      adm0 = admin1_properties["adm0_a3"].to_s.strip.upcase
      codes = [ iso2, adm0 ].select { |code| code.match?(/\A[A-Z]{2,3}\z/) }
      return [] if codes.empty?

      Rails.cache.fetch("anchor-region:districts:#{codes.join('-')}:v1", expires_in: 7.days) do
        local = RegionalDistrictBoundaryCatalog.all_features(country_codes: codes)
        local.any? ? local : GeoBoundariesService.adm2_features(adm0)
      end
    end

    # Bboxes are computed once per feature set so each anchor ray-casts only
    # the handful of shapes whose extent it falls inside.
    def index_features(features)
      Array(features).filter_map do |feature|
        rings = outer_rings(feature["geometry"])
        next if rings.empty?

        points = rings.flatten(1)
        lngs = points.map(&:first)
        lats = points.map(&:last)
        [ [ lats.min, lats.max, lngs.min, lngs.max ], feature ]
      end
    end

    def containing_feature(indexed, lat, lng)
      indexed.find do |bbox, feature|
        in_bbox?(bbox, lat, lng) && contains?(feature["geometry"], lat, lng)
      end&.last
    end

    def in_bbox?(bbox, lat, lng)
      south, north, west, east = bbox
      lat >= south && lat <= north && lng >= west && lng <= east
    end

    def contains?(geometry, lat, lng)
      outer_rings(geometry).any? { |ring| ring_contains?(ring, lat, lng) }
    end

    def outer_rings(geometry)
      case geometry&.fetch("type", nil)
      when "Polygon" then [ geometry["coordinates"].first ].compact
      when "MultiPolygon" then geometry["coordinates"].filter_map(&:first)
      else []
      end
    end

    # Shoelace over the outer rings, in squared degrees -- only ever compared
    # between two shapes containing the same point, so the latitude distortion
    # cancels out.
    def approx_area(feature)
      outer_rings(feature["geometry"]).sum do |ring|
        ring.each_cons(2).sum { |(x1, y1), (x2, y2)| (x1 * y2) - (x2 * y1) }.abs / 2.0
      end
    end

    def ring_contains?(ring, lat, lng)
      inside = false
      j = ring.size - 1
      ring.each_with_index do |point, i|
        xi, yi = point[0], point[1]
        xj, yj = ring[j][0], ring[j][1]
        if (yi > lat) != (yj > lat) && lng < (xj - xi) * (lat - yi) / (yj - yi) + xi
          inside = !inside
        end
        j = i
      end
      inside
    end

    def compact_region(feature, country)
      properties = feature.fetch("properties", {})
      compact_feature(
        name: properties["name_en"].presence || properties["name"].presence,
        level: "region",
        country: country,
        geometry: feature["geometry"]
      )
    end

    def compact_district(feature, country)
      properties = feature.fetch("properties", {})
      compact_feature(
        name: properties["name"].presence || properties["shapeName"].presence,
        level: "district",
        country: country,
        geometry: feature["geometry"]
      )
    end

    def compact_feature(name:, level:, country:, geometry:)
      {
        "type" => "Feature",
        "properties" => { "name" => name, "level" => level, "country_code" => country },
        "geometry" => geometry,
      }
    end

    # Natural Earth writes iso_a2 as "-99" where sovereignty is contested or
    # quirky (France, Norway); adm0_a3 is always real and the boundary
    # endpoint's country filter accepts either form.
    def country_code(properties)
      iso = properties["iso_a2"].to_s.strip.upcase
      return iso if iso.match?(/\A[A-Z]{2}\z/)

      adm0 = properties["adm0_a3"].to_s.strip.upcase
      adm0.match?(/\A[A-Z]{3}\z/) ? adm0 : nil
    end

    def cache_key(lat, lng)
      "anchor-region:v2:#{lat.to_f.round(2)}:#{lng.to_f.round(2)}"
    end
  end
end
