# The admin-1 region that contains a coordinate. The board uses it to draw a
# real region outline where it would otherwise guess with a circle, and the
# layer planner uses it to recover a country code for the many registry
# entities that never got one (59 of 63 live situations at last count).
#
# Resolution is a point-in-polygon scan over the Natural Earth admin-1 set
# that GeographyBoundaryService already fetches and caches. One scan resolves
# a whole batch of anchors, and each anchor's answer -- including "nothing
# contains it", which is normal for sea anchors like a strait -- is cached on
# its rounded coordinate, so the expensive path runs once per anchor per TTL,
# not once per request.
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

      indexed = indexed_features
      return {} if indexed.empty?

      anchors.each_with_object({}) do |anchor, out|
        lat = anchor[:lat].to_f
        lng = anchor[:lng].to_f
        entry = indexed.find do |bbox, feature|
          in_bbox?(bbox, lat, lng) && contains?(feature["geometry"], lat, lng)
        end
        compact = entry && compact_feature(entry.last)
        Rails.cache.write(cache_key(anchor[:lat], anchor[:lng]), compact || NONE, expires_in: CACHE_TTL)
        out[anchor[:id]] = compact
      end
    end

    # Bboxes are computed once per scan so each anchor ray-casts only the
    # handful of regions whose extent it falls inside.
    def indexed_features
      dataset = GeographyBoundaryService.fetch("admin1")
      features = dataset.is_a?(Hash) ? dataset["features"] : nil
      Array(features).filter_map do |feature|
        rings = outer_rings(feature["geometry"])
        next if rings.empty?

        points = rings.flatten(1)
        lngs = points.map(&:first)
        lats = points.map(&:last)
        [ [ lats.min, lats.max, lngs.min, lngs.max ], feature ]
      end
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

    def compact_feature(feature)
      properties = feature.fetch("properties", {})
      {
        "type" => "Feature",
        "properties" => {
          "name" => properties["name_en"].presence || properties["name"].presence,
          "country_code" => country_code(properties),
        },
        "geometry" => feature["geometry"],
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
      "anchor-region:v1:#{lat.to_f.round(2)}:#{lng.to_f.round(2)}"
    end
  end
end
