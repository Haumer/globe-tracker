class SituationSurfaceService
  SEVERITY_RANK = {
    "watch" => 1,
    "moderate" => 2,
    "high" => 3,
    "critical" => 4,
  }.freeze

  CHOKEPOINT_GEOMETRIES = {
    "hormuz" => {
      label: "Strait of Hormuz",
      scope: "corridor",
      rings: [
        [
          [25.55, 54.85],
          [26.35, 54.45],
          [27.55, 56.25],
          [27.15, 57.85],
          [25.85, 57.35],
          [25.25, 55.95],
        ],
      ],
    },
    "bab-el-mandeb" => {
      label: "Bab el-Mandeb",
      scope: "corridor",
      rings: [
        [
          [11.7, 41.8],
          [13.5, 41.7],
          [14.0, 43.5],
          [12.4, 44.6],
          [11.3, 43.2],
        ],
      ],
    },
    "suez" => {
      label: "Suez Canal",
      scope: "corridor",
      rings: [
        [
          [29.35, 31.05],
          [31.35, 31.05],
          [31.55, 32.55],
          [29.55, 32.75],
        ],
      ],
    },
    "bosphorus" => {
      label: "Bosphorus Strait",
      scope: "corridor",
      rings: [
        [
          [40.75, 28.55],
          [41.35, 28.55],
          [41.45, 29.35],
          [40.85, 29.45],
        ],
      ],
    },
  }.freeze

  APPROX_COUNTRY_GEOMETRIES = {
    "Iran" => [
      [
        [25.1, 44.0],
        [31.0, 44.3],
        [39.7, 47.3],
        [39.2, 53.9],
        [37.4, 61.5],
        [31.4, 63.3],
        [25.7, 61.4],
        [25.0, 55.4],
        [27.0, 50.0],
      ],
    ],
    "Ukraine" => [
      [
        [44.4, 22.1],
        [50.4, 22.1],
        [52.4, 25.5],
        [52.3, 33.8],
        [50.6, 40.2],
        [47.0, 39.2],
        [44.5, 35.2],
        [45.3, 28.0],
      ],
    ],
    "Levant" => [
      [
        [29.4, 33.6],
        [31.2, 34.0],
        [33.3, 34.7],
        [34.9, 35.1],
        [34.4, 36.9],
        [31.1, 36.3],
        [29.2, 35.0],
      ],
    ],
    "Nigeria" => [
      [
        [4.2, 2.7],
        [13.9, 3.2],
        [13.8, 14.6],
        [9.0, 14.8],
        [4.1, 8.2],
      ],
    ],
  }.freeze

  LOCAL_REGION_GEOMETRIES = {
    "Kyiv Region" => [[[49.6, 28.8], [51.8, 28.8], [51.9, 32.5], [49.8, 32.6]]],
    "Odesa Region" => [[[45.2, 28.7], [47.6, 28.7], [47.5, 31.9], [45.1, 32.1]]],
    "Gaza Strip" => [[[31.18, 34.17], [31.6, 34.2], [31.58, 34.56], [31.22, 34.45]]],
    "Kuwait" => [[[28.5, 46.45], [30.1, 46.45], [30.1, 48.65], [28.5, 48.65]]],
  }.freeze

  OUTAGE_COUNTRY_CODES = {
    "CM" => "Cameroon",
    "NA" => "Namibia",
    "SL" => "Sierra Leone",
  }.freeze

  class << self
    def build(conflict_snapshot: nil, conflict_payload: nil, include_live_events: true, now: Time.current)
      snapshot = conflict_snapshot || (conflict_payload ? nil : ConflictPulseSnapshotService.fetch_or_enqueue)
      payload = conflict_payload || snapshot&.payload.presence || ConflictPulseSnapshotService.empty_payload

      zones = Array(value(payload, :zones))
      strategic = Array(value(payload, :strategic_situations))
      hex_cells = Array(value(payload, :hex_cells))

      surfaces = []
      surfaces.concat(build_strategic_surfaces(strategic, now: now))
      surfaces.concat(build_systemic_surfaces(zones, now: now))
      surfaces.concat(build_zone_surfaces(zones, hex_cells, now: now))
      if include_live_events
        surfaces.concat(build_natural_event_surfaces(now: now))
        surfaces.concat(build_outage_surfaces(now: now))
      end

      surfaces = dedupe_surfaces(surfaces)
      surfaces.sort_by! { |surface| [surface[:render_order].to_i, -SEVERITY_RANK.fetch(surface[:severity_tier], 0), -surface[:attention_score].to_i] }

      {
        surfaces: surfaces,
        count: surfaces.size,
        generated_at: now.iso8601,
        snapshot_status: snapshot_status_for(snapshot, conflict_payload),
      }
    end

    private

    def build_strategic_surfaces(strategic, now:)
      strategic.filter_map do |item|
        node_id = value(item, :node_id).presence || value(item, :id).to_s.sub(/\Astrategic:/, "")
        geometry = geometry_for_chokepoint(node_id, value(item, :name))
        next unless geometry

        status = value(item, :status).presence || "monitoring"
        score = value(item, :strategic_score).to_i
        severity = if status == "critical" || score >= 88
          "critical"
        elsif status == "elevated" || score >= 65
          "high"
        elsif score >= 40
          "moderate"
        else
          "watch"
        end

        surface(
          id: "strategic:#{node_id}",
          label: geometry[:label] || value(item, :name) || "Strategic corridor",
          situation_class: "strategic_chokepoint",
          severity_tier: severity,
          attention_score: score,
          scope: geometry[:scope],
          geometry: { source: "curated_corridor", rings: geometry[:rings] },
          confidence: 0.78,
          evidence_summary: value(item, :pressure_summary).presence || "#{value(item, :direct_cluster_count).to_i} direct story clusters",
          source_count: value(item, :source_count).to_i,
          story_count: value(item, :direct_cluster_count).to_i,
          detected_at: value(item, :detected_at) || now.iso8601,
          render_order: 10,
          evidence: evidence_from_articles(value(item, :top_articles), value(item, :top_headlines)),
        )
      end
    end

    def build_systemic_surfaces(zones, now:)
      surfaces = []
      iran_zones = zones.select { |zone| zone_text(zone).match?(/\biran\b/i) && kinetic_conflict?(zone) }
      if iran_zones.any? { |zone| value(zone, :pulse_score).to_i >= 80 || verified_signal_count(zone) >= 10 }
        surfaces << systemic_surface(
          id: "system:iran",
          label: "Iran national war surface",
          country: "Iran",
          severity_tier: iran_zones.any? { |zone| value(zone, :pulse_score).to_i >= 88 } ? "critical" : "high",
          attention_score: iran_zones.map { |zone| value(zone, :pulse_score).to_i }.max,
          evidence_summary: "Kinetic reporting is broad enough to tint the national system; local hit areas still carry the sharper color.",
          source_count: iran_zones.sum { |zone| value(zone, :source_count).to_i },
          story_count: iran_zones.sum { |zone| value(zone, :story_count).to_i },
          now: now,
        )
      end

      ukraine_zones = zones.select { |zone| zone_text(zone).match?(/\bukraine|kyiv|odesa\b/i) && kinetic_conflict?(zone) }
      if ukraine_zones.count { |zone| value(zone, :pulse_score).to_i >= 65 } >= 2
        surfaces << systemic_surface(
          id: "system:ukraine",
          label: "Ukraine strike theater",
          country: "Ukraine",
          severity_tier: ukraine_zones.any? { |zone| value(zone, :pulse_score).to_i >= 85 } ? "high" : "moderate",
          attention_score: ukraine_zones.map { |zone| value(zone, :pulse_score).to_i }.max,
          evidence_summary: "Multiple Ukraine regions are active, so the national theater receives a low-opacity surface.",
          source_count: ukraine_zones.sum { |zone| value(zone, :source_count).to_i },
          story_count: ukraine_zones.sum { |zone| value(zone, :story_count).to_i },
          now: now,
        )
      end

      levant_zones = zones.select { |zone| zone_text(zone).match?(/\bisrael|gaza|lebanon|hezbollah|palestine\b/i) && kinetic_conflict?(zone) }
      if levant_zones.count { |zone| value(zone, :pulse_score).to_i >= 65 } >= 2
        surfaces << surface(
          id: "system:levant",
          label: "Israel-Lebanon-Gaza strike belt",
          situation_class: "kinetic_conflict",
          severity_tier: levant_zones.any? { |zone| value(zone, :pulse_score).to_i >= 88 } ? "critical" : "high",
          attention_score: levant_zones.map { |zone| value(zone, :pulse_score).to_i }.max,
          scope: "multi_region",
          geometry: { source: "curated_theater", rings: APPROX_COUNTRY_GEOMETRIES.fetch("Levant") },
          confidence: 0.72,
          evidence_summary: "Several local kinetic-reporting cells are active across the same operational belt.",
          source_count: levant_zones.sum { |zone| value(zone, :source_count).to_i },
          story_count: levant_zones.sum { |zone| value(zone, :story_count).to_i },
          detected_at: now.iso8601,
          render_order: 5,
          evidence: evidence_from_articles(levant_zones.flat_map { |zone| Array(value(zone, :top_articles)) }, levant_zones.flat_map { |zone| Array(value(zone, :top_headlines)) }),
        )
      end

      surfaces.compact
    end

    def build_zone_surfaces(zones, hex_cells, now:)
      zones.filter_map do |zone|
        lat = value(zone, :lat).to_f
        lng = value(zone, :lng).to_f
        next if lat.zero? && lng.zero?

        classification = situation_class_for(zone)
        next if classification == "reported_disruption" && diplomacy_only_text?(headline_text(zone))

        severity = severity_for_zone(zone, classification)
        next if severity == "watch"

        label = label_for_zone(zone, classification)
        boundary_ref = boundary_ref_for_zone(zone)
        geometry = boundary_ref ? nil : local_geometry_for(zone, hex_cells: hex_cells)

        surface(
          id: "zone:#{value(zone, :cell_key).presence || "#{lat.round(2)}:#{lng.round(2)}"}",
          label: label,
          situation_class: classification,
          severity_tier: severity,
          attention_score: value(zone, :pulse_score).to_i,
          scope: scope_for_zone(zone, classification),
          geometry: geometry,
          confidence: confidence_for_zone(zone, classification),
          evidence_summary: evidence_summary_for_zone(zone, classification),
          source_count: value(zone, :source_count).to_i,
          story_count: value(zone, :story_count).to_i,
          detected_at: value(zone, :detected_at) || now.iso8601,
          render_order: classification == "public_order" ? 34 : 30,
          evidence: evidence_from_articles(value(zone, :top_articles), value(zone, :top_headlines)),
          boundary_ref: boundary_ref,
          source: { conflict_cell_key: value(zone, :cell_key), theater: value(zone, :theater) },
        )
      end
    end

    def build_natural_event_surfaces(now:)
      NaturalEvent
        .where("event_date > ?", 72.hours.ago)
        .where(category_id: "severeStorms")
        .order(Arel.sql("COALESCE(magnitude_value, 0) DESC"), event_date: :desc)
        .limit(5)
        .filter_map do |event|
          next if event.latitude.blank? || event.longitude.blank?

          strength = event.magnitude_value.to_f
          severity = strength >= 85 ? "high" : strength >= 55 ? "moderate" : "watch"
          next if severity == "watch"

          surface(
            id: "natural:#{event.external_id}",
            label: event.title.presence || "Severe storm",
            situation_class: "natural_hazard",
            severity_tier: severity,
            attention_score: [strength.round, 40].max,
            scope: "local",
            geometry: event_geometry(event),
            confidence: 0.68,
            evidence_summary: [event.category_title, event.magnitude_value && "#{event.magnitude_value.to_i} #{event.magnitude_unit}".strip].compact.join(" - "),
            source_count: Array(event.sources).size,
            story_count: 1,
            detected_at: event.event_date&.iso8601 || now.iso8601,
            render_order: 40,
            evidence: [{ title: event.link.presence ? "NASA EONET event" : event.title, url: event.link }],
          )
        end
    rescue ActiveRecord::StatementInvalid
      []
    end

    def build_outage_surfaces(now:)
      outages = outage_summary
      outages.filter_map do |outage|
        score = value(outage, :score).to_f
        level = value(outage, :level).presence || "minor"
        next if score < 1_000 && !%w[moderate severe critical].include?(level)

        code = value(outage, :code).to_s.upcase
        name = value(outage, :name).presence || OUTAGE_COUNTRY_CODES[code] || code
        surface(
          id: "outage:#{code.presence || name}",
          label: "#{name} internet outage",
          situation_class: "internet_outage",
          severity_tier: level.in?(%w[severe critical]) ? "high" : "moderate",
          attention_score: [score / 100.0, 70].min.round,
          scope: "national",
          geometry: nil,
          boundary_ref: { dataset: "countries", iso_a2: code, name: name },
          confidence: 0.62,
          evidence_summary: "#{level} IODA outage signal, score #{score.round(1)}",
          source_count: value(outage, :eventCount).to_i,
          story_count: value(outage, :eventCount).to_i,
          detected_at: now.iso8601,
          render_order: 50,
          evidence: [],
        )
      end
    end

    def systemic_surface(id:, label:, country:, severity_tier:, attention_score:, evidence_summary:, source_count:, story_count:, now:)
      surface(
        id: id,
        label: label,
        situation_class: "kinetic_conflict",
        severity_tier: severity_tier,
        attention_score: attention_score,
        scope: "national",
        geometry: { source: "curated_country_fallback", rings: APPROX_COUNTRY_GEOMETRIES.fetch(country) },
        boundary_ref: { dataset: "countries", name: country },
        confidence: 0.74,
        evidence_summary: evidence_summary,
        source_count: source_count,
        story_count: story_count,
        detected_at: now.iso8601,
        render_order: 0,
        evidence: [],
      )
    end

    def situation_class_for(zone)
      return "public_order" if public_order?(zone)
      return "kinetic_conflict" if kinetic_conflict?(zone)

      "reported_disruption"
    end

    def severity_for_zone(zone, classification)
      score = value(zone, :pulse_score).to_i
      case classification
      when "kinetic_conflict"
        return "critical" if score >= 88 && (verified_signal_count(zone).positive? || kinetic_headline?(zone))
        return "high" if score >= 70
        return "moderate" if score >= 50
      when "public_order"
        return "high" if systemic_public_order?(zone) && score >= 75
        return "moderate" if score >= 50
      else
        return "moderate" if score >= 75
      end

      "watch"
    end

    def scope_for_zone(zone, classification)
      return "national" if classification == "public_order" && systemic_public_order?(zone)
      return "local" if classification == "public_order"
      return "local" if LOCAL_REGION_GEOMETRIES.key?(value(zone, :situation_name).to_s)

      "admin_region"
    end

    def label_for_zone(zone, classification)
      text = headline_text(zone)
      if classification == "public_order" && text.match?(/\bireland|irish|galway|refinery|fuel\b/i)
        return "Ireland fuel protests"
      end

      value(zone, :situation_name).presence || value(zone, :theater).presence || "Developing situation"
    end

    def local_geometry_for(zone, hex_cells:)
      name = value(zone, :situation_name).to_s
      return { source: "curated_local_region", rings: LOCAL_REGION_GEOMETRIES.fetch(name) } if LOCAL_REGION_GEOMETRIES.key?(name)

      nil
    end

    def boundary_ref_for_zone(zone)
      name = value(zone, :situation_name).to_s
      text = zone_text(zone)

      return { dataset: "admin1", name: "Kiev", admin: "Ukraine", iso_3166_2: "UA-32" } if name == "Kyiv Region" || text.match?(/\bkyiv|kiev\b/i)
      return { dataset: "admin1", name: "Odessa", admin: "Ukraine", iso_3166_2: "UA-51" } if name == "Odesa Region" || text.match?(/\bodesa|odessa\b/i)
      return { dataset: "admin1", name: "Gaza Strip", admin: "Gaza Strip", iso_3166_2: "PS-GZZ" } if text.match?(/\bgaza\b/i)
      return { dataset: "admin1", name: "HaZafon", admin: "Israel", iso_3166_2: "IL-Z" } if text.match?(/\bhezbollah|lebanon|safed|northern israel\b/i)

      nil
    end

    def event_geometry(event)
      points = Array(event.geometry_points).filter_map do |point|
        if point.is_a?(Hash)
          lat = point["lat"] || point[:lat] || point["latitude"] || point[:latitude]
          lng = point["lng"] || point[:lng] || point["lon"] || point[:lon] || point["longitude"] || point[:longitude]
          [lat.to_f, lng.to_f] if lat.present? && lng.present?
        elsif point.is_a?(Array) && point.size >= 2
          [point[1].to_f, point[0].to_f]
        end
      end

      if points.size >= 2
        lats = points.map(&:first)
        lngs = points.map(&:last)
        return rectangle(lats.min - 2.0, lats.max + 2.0, lngs.min - 2.0, lngs.max + 2.0, source: "event_track_bbox")
      end

      fallback_rectangle(event.latitude.to_f, event.longitude.to_f, 4.0, source: "event_buffer")
    end

    def fallback_rectangle(lat, lng, delta, source:)
      rectangle(lat - delta, lat + delta, lng - delta, lng + delta, source: source)
    end

    def rectangle(min_lat, max_lat, min_lng, max_lng, source:)
      {
        source: source,
        rings: [
          [
            [min_lat, min_lng],
            [min_lat, max_lng],
            [max_lat, max_lng],
            [max_lat, min_lng],
          ],
        ],
      }
    end

    def geometry_for_chokepoint(node_id, name)
      key = [node_id, name].compact.join(" ").downcase
      return CHOKEPOINT_GEOMETRIES["hormuz"] if key.include?("hormuz")
      return CHOKEPOINT_GEOMETRIES["bab-el-mandeb"] if key.match?(/bab|mandeb/)
      return CHOKEPOINT_GEOMETRIES["suez"] if key.include?("suez")
      return CHOKEPOINT_GEOMETRIES["bosphorus"] if key.include?("bosphorus")

      nil
    end

    def confidence_for_zone(zone, classification)
      base = classification == "kinetic_conflict" ? 0.68 : 0.55
      base += 0.12 if value(zone, :source_count).to_i >= 10
      base += 0.08 if kinetic_headline?(zone) || public_order?(zone)
      [base, 0.9].min.round(2)
    end

    def evidence_summary_for_zone(zone, classification)
      reports = value(zone, :count_24h).to_i
      sources = value(zone, :source_count).to_i
      case classification
      when "kinetic_conflict"
        "#{reports} reports from #{sources} sources; kinetic language controls severity, not thermal detections."
      when "public_order"
        "#{reports} reports from #{sources} sources; capped as public-order disruption unless evidence becomes systemic."
      else
        "#{reports} reports from #{sources} sources; no stronger class assigned yet."
      end
    end

    def public_order?(zone)
      return false if kinetic_headline?(zone)

      headline_text(zone).match?(/\b(protest|protests|demonstrat|unrest|riot|blockade|fuel|refinery|shortage|supply chain|strike action)\b/i)
    end

    def systemic_public_order?(zone)
      headline_text(zone).match?(/\b(government overthrow|government collapse|nationwide|state of emergency|martial law|coup|capital seized)\b/i)
    end

    def kinetic_conflict?(zone)
      zone_text(zone).match?(/\b(iran theater|russia-ukraine|ukraine|gaza|lebanon|hezbollah|israel-palestine|odesa|kyiv)\b/i) ||
        kinetic_headline?(zone) ||
        verified_signal_count(zone) >= 5
    end

    def kinetic_headline?(zone)
      text = headline_text(zone)
      return false if diplomacy_only_text?(text)

      text.match?(/\b(airstrike|missile|rocket|drone attack|shelling|strikes? on|war|ceasefire|hezbollah|killed .* strike|hit .* airbase|hit .* refinery)\b/i)
    end

    def diplomacy_only_text?(text)
      text.match?(/\b(talks?|negotiat|meeting|diplomacy|envoy|mediator|summit)\b/i) &&
        !text.match?(/\b(airstrike|missile|rocket|drone attack|shelling|killed|injured|attack on|attacks on|strikes? on|hit .* airbase|hit .* refinery)\b/i)
    end

    def verified_signal_count(zone)
      signals = value(zone, :cross_layer_signals)
      return 0 unless signals.respond_to?(:sum)

      signals.sum do |key, count|
        key.to_s.include?("verified") ? count.to_i : 0
      end
    end

    def headline_text(zone)
      articles = Array(value(zone, :top_articles)).map { |article| value(article, :title) }
      headlines = Array(value(zone, :top_headlines))
      (articles + headlines).compact.join(" ")
    end

    def zone_text(zone)
      [value(zone, :situation_name), value(zone, :theater), headline_text(zone)].compact.join(" ")
    end

    def evidence_from_articles(articles, headlines)
      article_rows = Array(articles).first(4).filter_map do |article|
        title = value(article, :title).presence
        next unless title

        {
          title: title,
          source: value(article, :publisher).presence || value(article, :source),
          url: value(article, :url),
          published_at: value(article, :published_at),
        }
      end
      return article_rows if article_rows.any?

      Array(headlines).first(4).map { |title| { title: title } }
    end

    def outage_summary
      cached = InternetOutageRefreshService.cached_summary
      return cached if cached.present?

      InternetOutage.where("started_at > ?", 24.hours.ago)
        .group_by(&:entity_code)
        .filter_map do |code, rows|
          strongest = rows.max_by { |row| row.score.to_f }
          next unless strongest

          {
            code: code,
            name: strongest.entity_name,
            score: rows.map { |row| row.score.to_f }.max,
            eventCount: rows.size,
            level: strongest.level,
          }
        end
    rescue ActiveRecord::StatementInvalid
      []
    end

    def dedupe_surfaces(surfaces)
      surfaces.each_with_object({}) do |surface, memo|
        existing = memo[surface[:id]]
        if existing.nil? || SEVERITY_RANK.fetch(surface[:severity_tier], 0) > SEVERITY_RANK.fetch(existing[:severity_tier], 0)
          memo[surface[:id]] = surface
        end
      end.values
    end

    def surface(id:, label:, situation_class:, severity_tier:, attention_score:, scope:, geometry:, confidence:, evidence_summary:, source_count:, story_count:, detected_at:, render_order:, evidence:, boundary_ref: nil, source: nil)
      {
        id: id,
        label: label,
        situation_class: situation_class,
        severity_tier: severity_tier,
        attention_score: attention_score.to_i,
        scope: scope,
        geometry_type: "polygon",
        geometry: geometry,
        boundary_ref: boundary_ref,
        confidence: confidence,
        evidence_summary: evidence_summary,
        source_count: source_count.to_i,
        story_count: story_count.to_i,
        detected_at: detected_at,
        render_order: render_order,
        evidence: Array(evidence).compact,
        source: source,
      }.compact
    end

    def snapshot_status_for(snapshot, conflict_payload)
      return "provided" if conflict_payload
      return "pending" unless snapshot
      return "ready" if snapshot.respond_to?(:fresh?) && snapshot.fresh? && snapshot.status == "ready"

      snapshot.respond_to?(:status) && snapshot.status == "error" ? "error" : "stale"
    end

    def value(record, key)
      return unless record
      return record[key] if record.respond_to?(:key?) && record.key?(key)

      string_key = key.to_s
      return record[string_key] if record.respond_to?(:key?) && record.key?(string_key)

      record.public_send(key) if record.respond_to?(key)
    end
  end
end
