class ShippingLaneMapService
  class CorridorGraph
    NEAREST_NODE_MAX_KM = 425.0

    NODES = CorridorGraphData::NODES
    EDGE_PATHS = CorridorGraphData::EDGE_PATHS
    EDGES = CorridorGraphData::EDGES
    NODE_KEYS_BY_LOCODE = CorridorGraphData::NODE_KEYS_BY_LOCODE
    NODE_KEYS_BY_CHOKEPOINT = CorridorGraphData::NODE_KEYS_BY_CHOKEPOINT

    class << self
      def baseline_corridors
        EDGES.filter_map do |left, right|
          path_points = expand_path_points([left, right])
          next if path_points.size < 2

          {
            id: "#{left}-#{right}",
            name: "#{NODES.fetch(left).fetch(:name)} to #{NODES.fetch(right).fetch(:name)}",
            kind: baseline_corridor_kind(left, right),
            path_points: path_points,
          }
        end
      end

      def route_points_for(anchor_sequence)
        return if anchor_sequence.blank?

        points = []
        anchor_sequence.each_cons(2) do |left, right|
          segment = segment_points(start_anchor: left, end_anchor: right)
          return if segment.blank?

          append_points(points, segment)
        end

        points if points.size >= 2
      end

      def segment_points(start_anchor:, end_anchor:)
        start_point = point_for_anchor(start_anchor)
        end_point = point_for_anchor(end_anchor)
        return if start_point.blank? || end_point.blank?

        start_node_key = node_key_for_anchor(start_anchor)
        end_node_key = node_key_for_anchor(end_anchor)

        node_keys = if start_node_key.present? && end_node_key.present?
          shortest_path(start_node_key, end_node_key)
        else
          nil
        end

        return [start_point, end_point] if node_keys.blank?

        points = expand_path_points(node_keys)
        points[0] = start_point
        points[-1] = end_point
        points
      end

      def point_for_anchor(anchor)
        lat = anchor&.dig(:lat)
        lng = anchor&.dig(:lng)
        return if lat.blank? || lng.blank?

        {
          name: anchor[:name],
          lat: lat.to_f,
          lng: lng.to_f,
          path_role: "anchor",
          anchor_kind: anchor[:kind],
        }.compact
      end

      def point_for_node(node_key)
        node = NODES.fetch(node_key.to_s)
        {
          key: node_key.to_s,
          name: node[:name],
          lat: node[:lat].to_f,
          lng: node[:lng].to_f,
          path_role: "corridor",
        }
      end

      def node_key_for_anchor(anchor)
        return if anchor.blank?

        if anchor[:kind].to_s == "chokepoint" && anchor[:key].present?
          chokepoint_key = NODE_KEYS_BY_CHOKEPOINT[anchor[:key].to_s]
          return chokepoint_key if chokepoint_key.present?
        end

        locode_key = NODE_KEYS_BY_LOCODE[anchor[:locode].to_s.upcase]
        return locode_key if locode_key.present?

        nearest_node_key(anchor)
      end

      def shortest_path(start_node_key, end_node_key)
        return [start_node_key.to_s] if start_node_key.to_s == end_node_key.to_s

        distances = Hash.new(Float::INFINITY)
        previous = {}
        queue = adjacency.keys.dup

        distances[start_node_key.to_s] = 0.0

        until queue.empty?
          current = queue.min_by { |node_key| distances[node_key] }
          break if current.blank? || distances[current].infinite?

          queue.delete(current)
          break if current == end_node_key.to_s

          adjacency[current].each do |neighbor, weight|
            next unless queue.include?(neighbor)

            candidate = distances[current] + weight
            next unless candidate < distances[neighbor]

            distances[neighbor] = candidate
            previous[neighbor] = current
          end
        end

        return if distances[end_node_key.to_s].infinite?

        build_path(previous, start_node_key.to_s, end_node_key.to_s)
      end

      private

      def baseline_corridor_kind(left, right)
        port_nodes = NODE_KEYS_BY_LOCODE.values
        (port_nodes.include?(left) || port_nodes.include?(right)) ? "approach" : "corridor"
      end

      def nearest_node_key(anchor)
        return if anchor[:lat].blank? || anchor[:lng].blank?

        node_key, node = NODES.min_by do |_candidate_key, candidate|
          haversine_km(anchor[:lat], anchor[:lng], candidate[:lat], candidate[:lng])
        end
        return if node_key.blank?

        distance_km = haversine_km(anchor[:lat], anchor[:lng], node[:lat], node[:lng])
        return if distance_km > NEAREST_NODE_MAX_KM

        node_key
      end

      def build_path(previous, start_node_key, end_node_key)
        path = [end_node_key]
        while (cursor = previous[path.first])
          path.unshift(cursor)
        end

        return if path.first != start_node_key

        path
      end

      def expand_path_points(node_keys)
        points = []
        node_keys.each_cons(2) do |left, right|
          segment = [
            point_for_node(left),
            *intermediate_points_for_edge(left, right),
            point_for_node(right),
          ]
          append_points(points, segment)
        end
        points
      end

      def intermediate_points_for_edge(left, right)
        forward_points = EDGE_PATHS[[left, right]]
        return normalize_intermediate_points(forward_points) if forward_points.present?

        reverse_points = EDGE_PATHS[[right, left]]
        return normalize_intermediate_points(reverse_points).reverse if reverse_points.present?

        []
      end

      def normalize_intermediate_points(points)
        Array(points).map do |point|
          {
            lat: point.fetch(:lat).to_f,
            lng: point.fetch(:lng).to_f,
            name: point[:name],
            path_role: "corridor",
          }.compact
        end
      end

      def adjacency
        @adjacency ||= begin
          graph = Hash.new { |hash, key| hash[key] = [] }
          EDGES.each do |left, right|
            weight = haversine_km(
              NODES.fetch(left)[:lat],
              NODES.fetch(left)[:lng],
              NODES.fetch(right)[:lat],
              NODES.fetch(right)[:lng]
            )
            graph[left] << [right, weight]
            graph[right] << [left, weight]
          end
          graph
        end
      end

      def append_points(collection, new_points)
        new_points.each do |point|
          next if point.blank?
          next if collection.last.present? && same_point?(collection.last, point)

          collection << point
        end
      end

      def same_point?(left, right)
        left[:lat].to_f.round(4) == right[:lat].to_f.round(4) &&
          left[:lng].to_f.round(4) == right[:lng].to_f.round(4)
      end

      def haversine_km(lat_a, lng_a, lat_b, lng_b)
        radius_km = 6371.0
        dlat = degrees_to_radians(lat_b.to_f - lat_a.to_f)
        dlng = degrees_to_radians(lng_b.to_f - lng_a.to_f)
        lat1 = degrees_to_radians(lat_a)
        lat2 = degrees_to_radians(lat_b)

        haversine = Math.sin(dlat / 2.0)**2 +
          Math.cos(lat1) * Math.cos(lat2) * Math.sin(dlng / 2.0)**2

        2.0 * radius_km * Math.atan2(Math.sqrt(haversine), Math.sqrt(1.0 - haversine))
      end

      def degrees_to_radians(value)
        value.to_f * Math::PI / 180.0
      end
    end
  end
end
