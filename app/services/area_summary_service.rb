class AreaSummaryService
  SEVERITY_ORDER = {
    "critical" => 0,
    "high" => 1,
    "medium" => 2,
    "low" => 3,
  }.freeze

  def initialize(area_workspace)
    @area_workspace = area_workspace
    @bounds = area_workspace.bounds_hash
  end

  def call
    movement = movement_summary
    assets = asset_summary
    chokepoints = filtered_chokepoints
    situations = filtered_situations
    insights = filtered_insights

    {
      brief: AreaBriefService.new(@area_workspace, bounds: @bounds).call,
      overview: overview_counts,
      signals: {
        headlines: headline_items,
        insights: insight_items,
        situations: situation_items,
      },
      movement: movement,
      assets: assets,
      infrastructure: infrastructure_summary(chokepoints),
      impacts: AreaImpactAssessmentService.new(
        @area_workspace,
        bounds: @bounds,
        movement: movement,
        assets: assets,
        chokepoints: chokepoints,
        situations: situations,
        insights: insights
      ).call,
      snapshots: snapshot_statuses,
    }
  end

  private

  def overview_counts
    {
      news: recent_news_scope.count,
      insights: filtered_insights.size,
      situations: filtered_situations.size,
      flights: fresh_flights_scope.count,
      ships: fresh_ships_scope.count,
      trains: current_trains_scope.count,
      notams: active_notams_scope.count,
      cameras: alive_cameras_scope.count,
    }
  end

  def movement_summary
    flights = fresh_flights_scope
    ships = fresh_ships_scope

    {
      flights_total: flights.count,
      flights_military: flights.where(military: true).count,
      flights_emergency: flights.where.not(emergency: [nil, ""]).count,
      ships_total: ships.count,
      ships_destinations: ships.where.not(destination: [nil, ""]).count,
      trains_total: current_trains_scope.count,
      trains_on_track: current_trains_scope.where.not(matched_railway_id: nil).count,
      notams_total: active_notams_scope.count,
    }
  end

  def asset_summary
    {
      chokepoints: filtered_chokepoints.size,
      airports: Airport.within_bounds(@bounds).count,
      military_bases: MilitaryBase.within_bounds(@bounds).count,
      cameras: alive_cameras_scope.count,
      power_plants: PowerPlant.within_bounds(@bounds).count,
    }
  end

  def infrastructure_summary(chokepoints = filtered_chokepoints)
    {
      chokepoints: chokepoints.first(4).map do |item|
        {
          name: value_for(item, :name),
          status: value_for(item, :status),
          ships_nearby: value_for(item, :ships_nearby)&.with_indifferent_access&.fetch(:total, 0),
          description: value_for(item, :description),
        }
      end,
      power_plants: PowerPlant.within_bounds(@bounds).order(capacity_mw: :desc).limit(4).map do |plant|
        {
          name: plant.name,
          fuel: plant.primary_fuel,
          capacity_mw: plant.capacity_mw&.round(0)&.to_i,
          country: plant.country_name.presence || plant.country_code,
        }
      end,
    }
  end

  def headline_items
    recent_news_scope
      .includes(:news_source)
      .order(published_at: :desc)
      .limit(6)
      .map do |event|
        {
          title: event.title.presence || event.name,
          publisher: event.news_source&.name.presence || event.name.presence || event.source,
          url: event.url,
          published_at: event.published_at,
          category: event.category,
        }
      end
  end

  def insight_items
    filtered_insights
      .sort_by do |item|
        [
          SEVERITY_ORDER.fetch(value_for(item, :severity).to_s, 10),
          -(parse_time(value_for(item, :detected_at) || value_for(item, :created_at))&.to_i || 0),
        ]
      end
      .first(5)
      .map do |insight|
        {
          title: value_for(insight, :title) || "Insight",
          description: value_for(insight, :description),
          severity: value_for(insight, :severity) || "medium",
          detected_at: value_for(insight, :detected_at) || value_for(insight, :created_at),
          insight_type: value_for(insight, :type),
        }
      end
  end

  def situation_items
    filtered_situations
      .sort_by { |item| -value_for(item, :pulse_score).to_i }
      .first(5)
      .map do |zone|
        {
          name: value_for(zone, :situation_name) || "Conflict theater",
          theater: value_for(zone, :theater),
          pulse_score: value_for(zone, :pulse_score).to_i,
          trend: value_for(zone, :escalation_trend),
          story_count: value_for(zone, :story_count).to_i,
          source_count: value_for(zone, :source_count).to_i,
        }
      end
  end

  def filtered_insights
    @filtered_insights ||= begin
      payload = insight_snapshot&.payload.presence || InsightSnapshotService.empty_payload
      Array(value_for(payload, :insights)).select do |insight|
        lat = value_for(insight, :lat)
        lng = value_for(insight, :lng)
        point_in_bounds?(lat, lng)
      end
    end
  end

  def filtered_situations
    @filtered_situations ||= begin
      payload = conflict_snapshot&.payload.presence || ConflictPulseSnapshotService.empty_payload
      Array(value_for(payload, :zones)).select do |zone|
        point_in_bounds?(value_for(zone, :lat), value_for(zone, :lng))
      end
    end
  end

  def filtered_chokepoints
    @filtered_chokepoints ||= begin
      payload = chokepoint_snapshot&.payload.presence || ChokepointSnapshotService.empty_payload
      Array(value_for(payload, :chokepoints)).select do |point|
        point_in_bounds?(value_for(point, :lat), value_for(point, :lng))
      end
    end
  end

  def recent_news_scope
    @recent_news_scope ||= NewsEvent.within_bounds(@bounds).where("published_at > ?", 24.hours.ago)
  end

  def fresh_flights_scope
    @fresh_flights_scope ||= Flight.where("updated_at > ?", 2.minutes.ago).within_bounds(@bounds)
  end

  def fresh_ships_scope
    @fresh_ships_scope ||= Ship.where("updated_at > ?", 6.hours.ago).within_bounds(@bounds)
  end

  def current_trains_scope
    @current_trains_scope ||= TrainObservation.current.within_bounds(@bounds)
  end

  def active_notams_scope
    @active_notams_scope ||= Notam.active.within_bounds(@bounds)
  end

  def alive_cameras_scope
    @alive_cameras_scope ||= Camera.alive.within_bounds(@bounds)
  end

  def insight_snapshot
    @insight_snapshot ||= InsightSnapshotService.fetch_or_enqueue
  end

  def conflict_snapshot
    @conflict_snapshot ||= ConflictPulseSnapshotService.fetch_or_enqueue
  end

  def chokepoint_snapshot
    @chokepoint_snapshot ||= ChokepointSnapshotService.fetch_or_enqueue
  end

  def snapshot_statuses
    {
      insights: snapshot_status_for(insight_snapshot),
      situations: snapshot_status_for(conflict_snapshot),
      chokepoints: snapshot_status_for(chokepoint_snapshot),
    }
  end

  def snapshot_status_for(snapshot)
    return "pending" unless snapshot
    return "ready" if snapshot.fresh? && snapshot.status == "ready"

    snapshot.status == "error" ? "error" : "stale"
  end

  def point_in_bounds?(lat, lng)
    return false unless lat.present? && lng.present?

    lat_f = lat.to_f
    lng_f = lng.to_f
    lat_f >= @bounds[:lamin] && lat_f <= @bounds[:lamax] &&
      lng_f >= @bounds[:lomin] && lng_f <= @bounds[:lomax]
  end

  def value_for(obj, key)
    return unless obj.respond_to?(:[])

    obj[key] || obj[key.to_s]
  end

  def parse_time(value)
    return if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
