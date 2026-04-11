class NearbySupportingSignalsService
  DEFAULT_WINDOW = 7.days
  DEFAULT_ITEM_LIMIT = 6
  SCOPE_BY_KIND = {
    "theater" => 6.0,
    "country" => 5.5,
    "chokepoint" => 2.2,
    "corridor" => 2.2,
    "pipeline" => 1.8,
    "power_plant" => 1.0,
    "port" => 1.4,
  }.freeze
  SUPPORTED_KINDS = SCOPE_BY_KIND.keys.freeze
  DEFAULT_SCOPE_DEG = 1.25

  def self.call(object_kind:, latitude:, longitude:, window: DEFAULT_WINDOW, item_limit: DEFAULT_ITEM_LIMIT)
    new(
      object_kind: object_kind,
      latitude: latitude,
      longitude: longitude,
      window: window,
      item_limit: item_limit
    ).call
  end

  def self.cross_layer_signals(object_kind:, latitude:, longitude:, window: DEFAULT_WINDOW, conflict_context: false)
    payload = call(
      object_kind: object_kind,
      latitude: latitude,
      longitude: longitude,
      window: window,
      item_limit: 0
    )
    return {} if payload.blank?

    strike_group = Array(payload[:groups]).find { |group| group[:key] == "strikes" }
    return {} unless strike_group.present?

    aggregate = strike_group[:aggregate].to_h
    {}.tap do |signals|
      thermal_count = aggregate[:thermal_count].to_i
      verified_count = aggregate[:verified_count].to_i
      signals[:verified_strike_reports_7d] = verified_count if verified_count.positive?
      signals[:strike_signals_7d] = thermal_count if thermal_count.positive? && (conflict_context || verified_count.positive?)
    end
  end

  def initialize(object_kind:, latitude:, longitude:, window:, item_limit:)
    @object_kind = object_kind.to_s
    @latitude = latitude
    @longitude = longitude
    @window = window
    @item_limit = item_limit
  end

  def call
    return nil unless supported_kind?
    return nil unless coordinates_present?

    groups = [build_strike_group].compact
    return nil unless groups.any?

    {
      scope_label: "#{(@window / 1.day).to_i}-day nearby scope",
      groups: groups,
      last_seen_at: groups.filter_map { |group| group[:last_seen_at] }.max,
    }
  end

  private

  def supported_kind?
    SUPPORTED_KINDS.include?(@object_kind)
  end

  def coordinates_present?
    @latitude.present? && @longitude.present?
  end

  def strike_bounds
    lat = @latitude.to_f
    lng = @longitude.to_f
    lat_radius = SCOPE_BY_KIND.fetch(@object_kind, DEFAULT_SCOPE_DEG)
    lng_scale = [Math.cos(lat * Math::PI / 180).abs, 0.25].max
    lng_radius = lat_radius / lng_scale

    {
      lamin: lat - lat_radius,
      lamax: lat + lat_radius,
      lomin: lng - lng_radius,
      lomax: lng + lng_radius,
    }
  end

  def build_strike_group
    thermal_scope = FireHotspot
      .where.not(acq_datetime: nil)
      .in_range(@window.ago, Time.current)
      .within_bounds(strike_bounds)
    thermal_items = thermal_scope.order(acq_datetime: :desc).limit(@item_limit).map do |hotspot|
      hotspot_signal_payload(hotspot)
    end
    thermal_count = thermal_scope.count

    verified_events = geoconfirmed_scope
    verified_count = verified_events.size
    verified_items = verified_events.first(@item_limit).map { |event| geoconfirmed_signal_payload(event) }

    items = (thermal_items + verified_items)
      .sort_by { |item| item[:at] || Time.zone.at(0) }
      .reverse
      .first(@item_limit)

    {
      key: "strikes",
      title: verified_count.positive? ? "Strike Reports / Thermal Detections" : "Thermal Detections",
      note: supporting_signal_note(verified_count: verified_count),
      aggregate: {
        thermal_count: thermal_count,
        verified_count: verified_count,
      },
      metrics: [
        { label: "Thermal detections / #{(@window / 1.day).to_i}d", value: thermal_count },
        { label: "Verified strike reports / #{(@window / 1.day).to_i}d", value: verified_count },
        {
          label: "Last Activity",
          value: items.first&.dig(:at),
          kind: :time,
        },
      ],
      items: items,
      last_seen_at: items.first&.dig(:at),
    }
  end

  def hotspot_signal_payload(hotspot)
    observed_at = hotspot.acq_datetime || hotspot.created_at
    title = hotspot.frp.to_f >= 80 ? "High-FRP thermal detection" : "Thermal detection"
    detail_bits = []
    detail_bits << "FRP #{format('%.1f', hotspot.frp)}" if hotspot.frp.present?
    detail_bits << "#{hotspot.brightness.round} brightness" if hotspot.brightness.present?
    detail_bits << (hotspot.daynight == "N" ? "night pass" : "day pass") if hotspot.daynight.present?

    {
      kind: "thermal",
      kind_label: "Thermal",
      title: title,
      meta: [
        hotspot.satellite.presence,
        hotspot.confidence.present? ? "#{hotspot.confidence} confidence" : nil,
      ].compact.join(" · "),
      detail: detail_bits.join(" · ").presence,
      at: observed_at,
    }
  end

  def supporting_signal_note(verified_count:)
    if verified_count.to_i.positive?
      "Verified strike reports carry the strike interpretation; thermal detections are only corroborating context."
    else
      "Raw satellite fire/heat detections. Treat as environmental or incident context unless corroborated by strike reporting."
    end
  end

  def geoconfirmed_scope
    model = "GeoconfirmedEvent".safe_constantize
    return [] unless model.present?
    return [] unless ActiveRecord::Base.connection.data_source_exists?(model.table_name)

    model
      .where.not(latitude: nil, longitude: nil)
      .within_bounds(strike_bounds)
      .where("posted_at > ? OR event_time > ?", @window.ago, @window.ago)
      .to_a
      .sort_by { |event| event.posted_at || event.event_time || Time.zone.at(0) }
      .reverse
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    []
  end

  def geoconfirmed_signal_payload(event)
    observed_at = event.posted_at || event.event_time || event.created_at

    {
      kind: "verified",
      kind_label: "Verified",
      title: event.title.presence || "GeoConfirmed strike report",
      meta: [
        event.map_region.to_s.tr("_", " ").titleize.presence,
        "GeoConfirmed",
      ].compact.join(" · "),
      detail: event.description.to_s.gsub(/<[^>]+>/, " ").squish.truncate(180).presence,
      at: observed_at,
    }
  end
end
