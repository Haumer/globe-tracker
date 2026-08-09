class OntologyRelationshipSyncService
  module InfrastructureDisruptionEventMethods
    private

    def recent_infrastructure_disruption_events(now:)
      recent_earthquakes(now: now) +
        recent_fire_clusters(now: now) +
        recent_fire_hotspots(now: now) +
        recent_natural_disruption_events(now: now) +
        recent_geoconfirmed_kinetic_events(now: now) +
        recent_news_kinetic_events(now: now)
    end

    def recent_earthquakes(now:)
      Earthquake.where("event_time >= ?", now - INFRASTRUCTURE_DISRUPTION_EVENT_WINDOW)
        .where.not(latitude: nil, longitude: nil)
        .where("COALESCE(magnitude, 0) >= ? OR tsunami = ? OR alert IS NOT NULL", 5.0, true)
        .order(event_time: :desc)
        .limit(INFRASTRUCTURE_DISRUPTION_EVENT_LIMIT)
        .map do |earthquake|
          {
            kind: :earthquake,
            record: earthquake,
            title: earthquake.title.presence || "M#{earthquake.magnitude.to_f.round(1)} earthquake",
            text: earthquake.title.to_s,
            event_family: "disaster",
            event_type: "earthquake",
            latitude: earthquake.latitude.to_f,
            longitude: earthquake.longitude.to_f,
            observed_at: earthquake.event_time || earthquake.fetched_at || earthquake.updated_at,
            radius_km: earthquake_disruption_radius_km(earthquake),
            severity: earthquake_disruption_severity(earthquake),
            confidence: earthquake_event_confidence(earthquake),
          }
        end
    end

    # Thermal-strike candidates stay per-detection: the signal there is a single
    # anomalous pixel in a conflict zone, and collapsing it into a fire complex
    # would erase exactly what makes it interesting.
    def recent_fire_hotspots(now:)
      FireHotspot.where("acq_datetime >= ?", now - INFRASTRUCTURE_DISRUPTION_EVENT_WINDOW)
        .where.not(latitude: nil, longitude: nil)
        .order(acq_datetime: :desc)
        .limit(INFRASTRUCTURE_DISRUPTION_EVENT_LIMIT)
        .filter_map do |fire|
          next unless relevant_fire_hotspot?(fire)
          next unless possible_thermal_strike?(fire)

          {
            kind: :thermal_strike,
            record: fire,
            title: "Thermal strike signal #{fire.external_id}",
            text: fire.external_id.to_s,
            event_family: "conflict",
            event_type: "thermal_strike",
            latitude: fire.latitude.to_f,
            longitude: fire.longitude.to_f,
            observed_at: fire.acq_datetime || fire.fetched_at || fire.updated_at,
            radius_km: fire_disruption_radius_km(fire),
            severity: fire_disruption_severity(fire),
            confidence: fire_event_confidence(fire),
          }
        end
    end

    # Wildfires enter the ontology as one event per fire complex, carrying every
    # satellite pass as evidence. Previously each pixel became its own
    # "disaster/fire_hotspot" event, which made it the largest event family in
    # the system -- 155,579 events, none of them a distinct fire.
    def recent_fire_clusters(now:)
      FireCluster.notable
        .where(last_detected_at: (now - INFRASTRUCTURE_DISRUPTION_EVENT_WINDOW)..)
        .strongest
        .limit(INFRASTRUCTURE_DISRUPTION_EVENT_LIMIT)
        # Every cluster's passes become evidence, so load them in one query
        # rather than one per cluster.
        .preload(:fire_observations)
        .map do |cluster|
          {
            kind: :fire,
            record: cluster,
            title: "#{cluster.tier.capitalize} fire #{cluster.external_id}",
            text: cluster.external_id.to_s,
            event_family: "disaster",
            event_type: "fire",
            latitude: cluster.latitude.to_f,
            longitude: cluster.longitude.to_f,
            observed_at: cluster.last_detected_at || cluster.computed_at,
            started_at: cluster.first_detected_at,
            radius_km: fire_cluster_disruption_radius_km(cluster),
            severity: cluster.tier,
            confidence: fire_cluster_confidence(cluster),
            # Sorted in memory rather than with the chronological scope, which
            # would issue a fresh query per cluster and undo the preload.
            evidence: cluster.fire_observations.sort_by(&:acq_datetime),
          }
        end
    end

    # Bigger fires threaten a wider area, but the footprint is what matters, not
    # raw radiance -- a 50,000 MW complex is not 500x the reach of a 100 MW one.
    def fire_cluster_disruption_radius_km(cluster)
      spread_km = ((cluster.max_latitude.to_f - cluster.min_latitude.to_f).abs * 111.0)
      [[spread_km, Math.sqrt([cluster.pixel_count, 1].max) * 0.4].max, 50.0].min.round(1)
    end

    def fire_cluster_confidence(cluster)
      # Independent platforms seeing the same fire is the strongest signal we have.
      base = { "extreme" => 0.9, "major" => 0.8, "moderate" => 0.65 }.fetch(cluster.tier, 0.5)
      corroboration = [(cluster.satellites || []).size - 1, 0].max * 0.03
      [base + corroboration, 0.98].min.round(2)
    end

    def recent_natural_disruption_events(now:)
      NaturalEvent.where("event_date >= ?", now - INFRASTRUCTURE_DISRUPTION_EVENT_WINDOW)
        .where.not(latitude: nil, longitude: nil)
        .where(category_title: INFRASTRUCTURE_DISRUPTION_NATURAL_EVENT_CATEGORIES)
        .order(event_date: :desc)
        .limit(INFRASTRUCTURE_DISRUPTION_EVENT_LIMIT)
        .map do |event|
          {
            kind: :natural_event,
            record: event,
            title: event.title.presence || event.category_title.presence || "Natural event",
            text: [event.title, event.category_title].compact.join(" "),
            event_family: "disaster",
            event_type: "natural_event",
            latitude: event.latitude.to_f,
            longitude: event.longitude.to_f,
            observed_at: event.event_date || event.fetched_at || event.updated_at,
            radius_km: natural_event_disruption_radius_km(event),
            severity: natural_event_disruption_severity(event),
            confidence: natural_event_confidence(event),
          }
        end
    end

    def recent_geoconfirmed_kinetic_events(now:)
      GeoconfirmedEvent.where("COALESCE(posted_at, event_time, fetched_at) >= ?", now - INFRASTRUCTURE_DISRUPTION_EVENT_WINDOW)
        .where.not(latitude: nil, longitude: nil)
        .order(Arel.sql("COALESCE(posted_at, event_time, fetched_at) DESC"))
        .limit(INFRASTRUCTURE_DISRUPTION_EVENT_LIMIT)
        .filter_map do |event|
          text = [event.title, event.description, event.icon_key].compact.join(" ")
          next unless kinetic_event_text?(text)

          {
            kind: :geoconfirmed_strike,
            record: event,
            title: geoconfirmed_event_title(event),
            text: text,
            event_family: "conflict",
            event_type: "geoconfirmed_strike",
            latitude: event.latitude.to_f,
            longitude: event.longitude.to_f,
            observed_at: event.posted_at || event.event_time || event.fetched_at || event.updated_at,
            radius_km: 45.0,
            severity: disruption_language?(text) ? "high" : "medium",
            confidence: 0.82,
          }
        end
    end

    def geoconfirmed_event_title(event)
      description_title = geoconfirmed_description_title(event.description)
      return description_title if description_title.present?

      title = event.title.to_s.scrub("").squish
      return title if title.present? && !geoconfirmed_date_only_title?(title)

      location_hint = event.map_region.to_s.tr("_-", " ").squish.presence
      coordinate_hint = format("%.4f, %.4f", event.latitude.to_f, event.longitude.to_f)
      date_hint = (event.posted_at || event.event_time)&.strftime("%d %b %Y")
      ["Geoconfirmed strike", location_hint, coordinate_hint, date_hint].compact_blank.join(" · ")
    end

    def geoconfirmed_description_title(description)
      first_line = description.to_s.lines.map do |line|
        line.to_s.strip.sub(/\ASource\(s\):.*\z/i, "").sub(/\AGeolocation\(s\):.*\z/i, "").strip
      end.find(&:present?)
      return if first_line.blank?

      first_line.to_s.scrub("").squish.slice(0, 220)
    end

    def geoconfirmed_date_only_title?(title)
      title.match?(/\A\d{1,2}\s+[[:alpha:]]{3,9}\s+\d{4}\z/)
    end

    def recent_news_kinetic_events(now:)
      NewsStoryCluster.where("last_seen_at >= ?", now - INFRASTRUCTURE_DISRUPTION_EVENT_WINDOW)
        .where(event_family: %w[conflict security infrastructure transport])
        .where(event_type: INFRASTRUCTURE_KINETIC_EVENT_TYPES)
        .where.not(latitude: nil, longitude: nil)
        .where("source_count >= ? OR verification_status IN (?)", 2, CORROBORATED_NEWS_STATUSES)
        .order(last_seen_at: :desc)
        .limit(INFRASTRUCTURE_DISRUPTION_EVENT_LIMIT)
        .map do |cluster|
          event = NewsOntologySyncService.sync_story_cluster(cluster)
          text = [cluster.canonical_title, cluster.location_name].compact.join(" ")
          {
            kind: :news_kinetic_event,
            record: cluster,
            ontology_event: event,
            title: cluster.canonical_title.presence || "Reported kinetic event",
            text: text,
            event_family: cluster.event_family,
            event_type: cluster.event_type,
            latitude: cluster.latitude.to_f,
            longitude: cluster.longitude.to_f,
            observed_at: cluster.last_seen_at || cluster.first_seen_at || cluster.updated_at,
            radius_km: 55.0,
            severity: disruption_language?(text) ? "high" : "medium",
            confidence: [cluster.cluster_confidence.to_f, 0.9].min,
          }
        end
    end

    def earthquake_disruption_radius_km(earthquake)
      magnitude = earthquake.magnitude.to_f
      [[40.0 + (magnitude * 22.0), 90.0].max, 260.0].min
    end

    def fire_disruption_radius_km(fire)
      base = fire.frp.to_f >= 50.0 ? 45.0 : 25.0
      fire.confidence.to_s.in?(%w[high h]) || fire.confidence.to_f >= 80.0 ? base + 10.0 : base
    end

    def natural_event_disruption_radius_km(event)
      return 120.0 if event.category_title.to_s.in?(["Severe Storms", "Floods"])
      return 90.0 if event.category_title.to_s == "Volcanoes"

      60.0
    end

    def earthquake_disruption_severity(earthquake)
      return "critical" if earthquake.magnitude.to_f >= 7.0 || earthquake.alert == "red" || earthquake.tsunami?
      return "high" if earthquake.magnitude.to_f >= 6.0 || earthquake.alert.in?(%w[orange yellow])
      return "medium" if earthquake.magnitude.to_f >= 5.0

      "low"
    end

    def fire_disruption_severity(fire)
      return "high" if fire.confidence.to_s.in?(%w[high h]) && fire.frp.to_f >= 50.0
      return "medium" if fire.confidence.to_s.in?(%w[high h nominal n])
      return "medium" if fire.confidence.to_s.match?(/\A\d+(\.\d+)?\z/) && fire.confidence.to_f >= 60.0

      "low"
    end

    def natural_event_disruption_severity(event)
      return "high" if event.magnitude_value.to_f >= 5.0
      return "medium" if event.category_title.to_s.in?(["Volcanoes", "Wildfires", "Floods", "Severe Storms"])

      "low"
    end

    def earthquake_event_confidence(earthquake)
      confidence = 0.62
      confidence += [earthquake.magnitude.to_f / 10.0, 0.2].min
      confidence += 0.08 if earthquake.alert.present?
      confidence += 0.05 if earthquake.tsunami?
      [confidence, 0.92].min.round(2)
    end

    def fire_event_confidence(fire)
      confidence = fire.confidence.to_s.in?(%w[high h]) || fire.confidence.to_f >= 80.0 ? 0.76 : 0.62
      confidence += [fire.frp.to_f / 300.0, 0.1].min if fire.frp.present?
      [confidence, 0.9].min.round(2)
    end

    def natural_event_confidence(event)
      confidence = 0.6
      confidence += 0.08 if event.sources.present?
      confidence += 0.05 if event.geometry_points.present?
      [confidence, 0.85].min.round(2)
    end

    def relevant_fire_hotspot?(fire)
      confidence = fire.confidence.to_s.downcase
      return true if %w[high h nominal n].include?(confidence)
      return confidence.to_f >= 60.0 if confidence.match?(/\A\d+(\.\d+)?\z/)

      false
    end

    def possible_thermal_strike?(fire)
      return false unless fire.latitude.present? && fire.longitude.present?

      confidence = fire.confidence.to_s.downcase
      is_confident = %w[high h].include?(confidence) || confidence.to_f >= 80.0
      return false unless is_confident

      in_conflict_zone = Api::FireHotspotsController::CONFLICT_COUNTRIES.any? do |_code, bounds|
        bounds[:lat].cover?(fire.latitude) && bounds[:lng].cover?(fire.longitude)
      end
      return false unless in_conflict_zone

      fire.daynight == "N" || fire.frp.to_f > 20.0 || fire.brightness.to_f > 360.0
    end

    def kinetic_event_text?(text)
      text.to_s.match?(/\b(airstrike|missile|drone|shelling|strike|strikes|struck|attack|attacks|explosion|blast)\b/i)
    end

    def disruption_language?(text)
      text.to_s.match?(/\b(hit|struck|damag(?:e|ed|ing)?|destroy(?:ed|s)?|explosion|blast|fire|burn(?:ed|ing)?|closed|closure|halt(?:ed)?|suspend(?:ed)?|outage|blackout|shut(?:down)?|disabled|disrupt(?:ed|ion)?)\b/i)
    end
  end
end
