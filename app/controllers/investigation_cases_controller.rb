class InvestigationCasesController < ApplicationController
  STRIKE_SIGNAL_WINDOW = 7.days
  STRIKE_SIGNAL_LIMIT = 6
  STRIKE_SCOPE_BY_KIND = {
    "theater" => 6.0,
    "country" => 5.5,
    "chokepoint" => 2.2,
    "corridor" => 2.2,
    "pipeline" => 1.8,
    "power_plant" => 1.0,
    "port" => 1.4,
  }.freeze
  DEFAULT_STRIKE_SCOPE_DEG = 1.25

  before_action :set_investigation_case, only: [:show, :update]
  before_action :set_assignable_users, only: [:new, :show, :update]

  def index
    @investigation_cases = current_user.investigation_cases
      .includes(:assignee, :case_objects, case_notes: :user)
      .recent
    @meta_title = "Cases | GlobeTracker"
    @meta_description = "Track pinned objects, analyst notes, and durable operational context across your investigation cases."
  end

  def new
    @source_object = source_object_payload
    @return_to_globe = normalized_return_to
    @available_cases = current_user.investigation_cases.includes(:assignee).recent.limit(10)
    @investigation_case = current_user.investigation_cases.build(
      title: default_case_title(@source_object),
      summary: @source_object[:summary],
      status: "open",
      severity: default_case_severity(@source_object),
      assignee: current_user
    )
    @meta_title = "New Case | GlobeTracker"
    @meta_description = @source_object[:title].present? ? "Create a case for #{@source_object[:title]} and preserve the current operating picture." : "Create a new investigation case."
  end

  def show
    @return_to_globe = normalized_return_to
    prepare_case_show_state
    @meta_title = "#{@investigation_case.title} | GlobeTracker"
    @meta_description = @investigation_case.summary.presence || "#{@case_objects.size} pinned objects and #{@case_notes.size} notes in this investigation case."
  end

  def create
    @investigation_case = current_user.investigation_cases.build(investigation_case_params)
    @investigation_case.assignee ||= current_user
    attach_source_object(@investigation_case, source_object_params)

    if @investigation_case.save
      redirect_to case_path(@investigation_case, return_to: normalized_return_to), notice: "Case created."
    else
      @source_object = source_object_payload
      @return_to_globe = normalized_return_to
      @available_cases = current_user.investigation_cases.includes(:assignee).recent.limit(10)
      set_assignable_users
      @meta_title = "New Case | GlobeTracker"
      @meta_description = "Create a new investigation case."
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @investigation_case.update(investigation_case_update_params)
      redirect_to case_path(@investigation_case, return_to: normalized_return_to), notice: "Case updated."
    else
      @return_to_globe = normalized_return_to
      prepare_case_show_state
      @meta_title = "#{@investigation_case.title} | GlobeTracker"
      @meta_description = @investigation_case.summary.presence || "#{@case_objects.size} pinned objects and #{@case_notes.size} notes in this investigation case."
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_investigation_case
    @investigation_case = current_user.investigation_cases.find(params[:id])
  end

  def investigation_case_params
    permitted = params.fetch(:investigation_case, {}).permit(:title, :summary, :status, :severity, :assignee_id)
    normalize_case_params(permitted)
  end

  def investigation_case_update_params
    permitted = params.require(:investigation_case).permit(:title, :summary, :status, :severity, :assignee_id)
    normalize_case_params(permitted)
  end

  def attach_source_object(investigation_case, payload)
    return if payload.blank?

    investigation_case.case_objects.build(InvestigationCaseObject.attributes_from_payload(payload))
  end

  def source_object_params
    params.permit(
      source_object: [
        :object_kind,
        :object_identifier,
        :title,
        :summary,
        :object_type,
        :latitude,
        :longitude,
        { source_context: {} }
      ]
    )[:source_object]
  end

  def source_object_payload
    payload = source_object_params
    return {} if payload.blank?

    InvestigationCaseObject.attributes_from_payload(payload)
  end

  def normalize_case_params(permitted)
    attrs = permitted.to_h
    attrs["assignee_id"] = nil if attrs["assignee_id"].blank?
    attrs
  end

  def set_assignable_users
    @assignable_users = User.order(:email)
  end

  def prepare_case_show_state
    @case_objects = @investigation_case.case_objects
    @case_notes = @investigation_case.case_notes.includes(:user)
    @case_note = @investigation_case.case_notes.build
    @available_cases = current_user.investigation_cases.where.not(id: @investigation_case.id).includes(:assignee).recent.limit(10)
    @case_workspace = build_case_workspace(@case_objects.first)
  end

  def build_case_workspace(primary_object)
    return nil unless primary_object

    node_context = resolve_case_object_context(primary_object)
    theater_brief_payload = resolve_case_theater_brief(primary_object)
    source_context = merged_case_source_context(primary_object, theater_brief_payload)
    strike_signals = case_workspace_strike_signals(primary_object)

    {
      primary_object: primary_object,
      node_context: node_context,
      source_context: source_context,
      assessment: case_workspace_assessment(primary_object, source_context, theater_brief_payload),
      why_we_believe_it: case_workspace_why_we_believe_it(primary_object, source_context, theater_brief_payload),
      key_developments: case_workspace_key_developments(primary_object, node_context, theater_brief_payload),
      watch_next: case_workspace_watch_next(primary_object, source_context, theater_brief_payload),
      metrics: case_workspace_metrics(primary_object, source_context, node_context),
      strike_signals: strike_signals,
      graph_groups: case_workspace_graph_groups(node_context),
      timeline_entries: case_workspace_timeline(primary_object, theater_brief_payload),
      theater_brief_status: theater_brief_payload&.dig(:status),
      theater_brief_generated_at: parsed_workspace_time(theater_brief_payload&.dig(:generated_at)),
      theater_brief_scope_key: theater_brief_payload&.dig(:scope_key),
    }
  end

  def resolve_case_object_context(case_object)
    NodeContextService.resolve(kind: case_object.object_kind, id: case_object.object_identifier).deep_symbolize_keys
  rescue NodeContextService::UnsupportedNodeError, NodeContextService::NodeNotFoundError
    nil
  end

  def resolve_case_theater_brief(case_object)
    return nil unless case_object.object_kind.to_s == "theater"

    payload = TheaterBriefService.fetch_or_enqueue(
      theater: case_object.object_identifier,
      cell_key: case_object.source_context["cell_key"]
    )
    payload&.deep_symbolize_keys
  rescue StandardError => error
    Rails.logger.warn("Case workspace theater brief failed for #{case_object.object_identifier}: #{error.class}: #{error.message}")
    nil
  end

  def merged_case_source_context(case_object, theater_brief_payload)
    brief_source = theater_brief_payload&.dig(:source_context) || {}
    case_object.source_context.to_h.deep_symbolize_keys.merge(brief_source.deep_symbolize_keys)
  end

  def case_workspace_assessment(primary_object, source_context, theater_brief_payload)
    brief_assessment = theater_brief_payload&.dig(:brief, :assessment).presence
    return brief_assessment if brief_assessment.present?

    if primary_object.object_kind.to_s == "theater"
      pulse = source_context[:pulse_score]
      trend = source_context[:escalation_trend].presence || source_context[:trend].presence || "active"
      reports = source_context[:reports_24h] || source_context[:count_24h]
      sources = source_context[:sources] || source_context[:source_count]
      bits = []
      bits << "Pulse #{pulse}" if pulse.present?
      bits << "#{trend.to_s.tr('_', ' ')} pressure"
      bits << "#{reports} reports / 24h" if reports.present?
      bits << "#{sources} sources" if sources.present?
      return bits.join(" · ") if bits.any?
    end

    primary_object.summary.presence || "Use this case workspace to track the operating picture, durable evidence, and next actions."
  end

  def case_workspace_why_we_believe_it(primary_object, source_context, theater_brief_payload)
    items = Array(theater_brief_payload&.dig(:brief, :why_we_believe_it)).map(&:presence).compact
    return items.first(4) if items.any?

    return [] unless primary_object.object_kind.to_s == "theater"

    fallback = []
    reports = source_context[:reports_24h] || source_context[:count_24h]
    sources = source_context[:sources] || source_context[:source_count]
    stories = source_context[:stories] || source_context[:story_count]
    spike = source_context[:spike_ratio]

    fallback << "#{reports} reports in the last 24 hours are carrying this theater." if reports.present?
    fallback << "#{sources} sources are contributing to the current read." if sources.present?
    fallback << "#{stories} story clusters are reinforcing the operating picture." if stories.present?
    fallback << "Reporting is running at #{spike}x baseline." if spike.present?
    fallback
  end

  def case_workspace_key_developments(primary_object, node_context, theater_brief_payload)
    items = Array(theater_brief_payload&.dig(:brief, :key_developments)).map(&:presence).compact
    return items.first(4) if items.any?

    evidence_labels = Array(node_context&.dig(:evidence)).first(4).filter_map do |item|
      [item[:label], item[:meta]].compact.join(" · ").presence
    end
    return evidence_labels if evidence_labels.any?

    [primary_object.summary].compact_blank.first(1)
  end

  def case_workspace_watch_next(primary_object, source_context, theater_brief_payload)
    items = Array(theater_brief_payload&.dig(:brief, :watch_next)).map(&:presence).compact
    return items.first(4) if items.any?

    return [] unless primary_object.object_kind.to_s == "theater"

    reports = source_context[:reports_24h] || source_context[:count_24h]
    sources = source_context[:sources] || source_context[:source_count]

    fallback = []
    fallback << "Watch whether fresh reporting pushes above the current #{reports} reports / 24h pace." if reports.present?
    fallback << "Additional independent sourcing would strengthen confidence in the current theater read." if sources.to_i < 4
    fallback << "A drop in fresh corroborating reporting would weaken the current escalation signal."
    fallback.uniq.first(3)
  end

  def case_workspace_metrics(primary_object, source_context, node_context)
    metrics = []

    if primary_object.object_kind.to_s == "theater"
      metrics << { label: "Pulse", value: source_context[:pulse_score] } if source_context[:pulse_score].present?
      metrics << { label: "Reports / 24h", value: source_context[:reports_24h] || source_context[:count_24h] } if (source_context[:reports_24h] || source_context[:count_24h]).present?
      metrics << { label: "Sources", value: source_context[:sources] || source_context[:source_count] } if (source_context[:sources] || source_context[:source_count]).present?
      metrics << { label: "Stories", value: source_context[:stories] || source_context[:story_count] } if (source_context[:stories] || source_context[:story_count]).present?
      metrics << { label: "Spike", value: "#{source_context[:spike_ratio]}x" } if source_context[:spike_ratio].present?
      metrics << { label: "Trend", value: source_context[:escalation_trend].to_s.tr("_", " ") } if source_context[:escalation_trend].present?
    end

    metrics << { label: "Actors", value: Array(node_context&.dig(:memberships)).size } if Array(node_context&.dig(:memberships)).any?
    metrics << { label: "Evidence", value: Array(node_context&.dig(:evidence)).size } if Array(node_context&.dig(:evidence)).any?
    metrics << { label: "Linked nodes", value: Array(node_context&.dig(:relationships)).size } if Array(node_context&.dig(:relationships)).any?

    metrics.first(6)
  end

  def case_workspace_graph_groups(node_context)
    return [] unless node_context.present?

    [
      {
        title: "Actors",
        items: Array(node_context[:memberships]).first(5).map do |membership|
          {
            label: membership.dig(:node, :name) || membership[:role],
            meta: [membership[:role], membership[:confidence] ? "#{(membership[:confidence].to_f * 100).round}% confidence" : nil].compact.join(" · "),
            node: membership[:node],
          }
        end
      },
      {
        title: "Recorded evidence",
        items: Array(node_context[:evidence]).first(6).map do |item|
          {
            label: item[:label],
            meta: [item[:role], item[:meta]].compact.join(" · "),
            evidence: item,
          }
        end
      },
      {
        title: "Linked nodes",
        items: Array(node_context[:relationships]).first(6).map do |relationship|
          {
            label: relationship.dig(:node, :name) || relationship[:relation_type],
            meta: [relationship[:relation_type]&.tr("_", " "), relationship[:confidence] ? "#{(relationship[:confidence].to_f * 100).round}% confidence" : nil].compact.join(" · "),
            node: relationship[:node],
          }
        end
      }
    ].select { |group| group[:items].any? }
  end

  def case_workspace_strike_signals(primary_object)
    return nil unless case_workspace_supports_strike_signals?(primary_object)

    coordinates = case_workspace_coordinates(primary_object)
    return nil unless coordinates.present?

    bounds = case_workspace_strike_signal_bounds(primary_object.object_kind, coordinates)
    thermal_scope = FireHotspot
      .where.not(acq_datetime: nil)
      .in_range(STRIKE_SIGNAL_WINDOW.ago, Time.current)
      .within_bounds(bounds)
    thermal_signals = thermal_scope.order(acq_datetime: :desc).limit(STRIKE_SIGNAL_LIMIT).to_a
    thermal_count = thermal_scope.count
    geoconfirmed_events = case_workspace_geoconfirmed_signals(bounds)
    verified_count = geoconfirmed_events.size
    geoconfirmed_signals = geoconfirmed_events.first(STRIKE_SIGNAL_LIMIT)

    items = (
      thermal_signals.map { |hotspot| case_workspace_hotspot_signal_payload(hotspot) } +
      geoconfirmed_signals.map { |event| case_workspace_geoconfirmed_signal_payload(event) }
    ).compact
      .sort_by { |item| item[:at] || Time.zone.at(0) }
      .reverse
      .first(STRIKE_SIGNAL_LIMIT)

    {
      scope_label: "7-day nearby scope",
      thermal_count: thermal_count,
      verified_count: verified_count,
      total_count: thermal_count + verified_count,
      last_seen_at: items.first&.dig(:at),
      items: items,
    }
  end

  def case_workspace_coordinates(primary_object)
    return nil unless primary_object.latitude.present? && primary_object.longitude.present?

    {
      latitude: primary_object.latitude.to_f,
      longitude: primary_object.longitude.to_f,
    }
  end

  def case_workspace_supports_strike_signals?(primary_object)
    %w[theater chokepoint corridor pipeline power_plant port country].include?(primary_object.object_kind.to_s)
  end

  def case_workspace_strike_signal_bounds(object_kind, coordinates)
    lat = coordinates[:latitude]
    lng = coordinates[:longitude]
    lat_radius = STRIKE_SCOPE_BY_KIND.fetch(object_kind.to_s, DEFAULT_STRIKE_SCOPE_DEG)
    lng_scale = [Math.cos(lat * Math::PI / 180).abs, 0.25].max
    lng_radius = lat_radius / lng_scale

    {
      lamin: lat - lat_radius,
      lamax: lat + lat_radius,
      lomin: lng - lng_radius,
      lomax: lng + lng_radius,
    }
  end

  def case_workspace_hotspot_signal_payload(hotspot)
    observed_at = hotspot.acq_datetime || hotspot.created_at
    title = hotspot.frp.to_f >= 80 ? "High-FRP thermal strike signal" : "Thermal strike signal"
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

  def case_workspace_geoconfirmed_signals(bounds)
    model = "GeoconfirmedEvent".safe_constantize
    return [] unless model.present?
    return [] unless ActiveRecord::Base.connection.data_source_exists?(model.table_name)

    model
      .where.not(latitude: nil, longitude: nil)
      .within_bounds(bounds)
      .where("posted_at > ? OR event_time > ?", STRIKE_SIGNAL_WINDOW.ago, STRIKE_SIGNAL_WINDOW.ago)
      .to_a
      .sort_by { |event| event.posted_at || event.event_time || Time.zone.at(0) }
      .reverse
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    []
  end

  def case_workspace_geoconfirmed_signal_payload(event)
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

  def case_workspace_timeline(primary_object, theater_brief_payload)
    entries = []
    entries << { kind: "note", title: "Case opened", meta: @investigation_case.case_code, at: @investigation_case.created_at }
    entries << { kind: "update", title: "Primary focus added", meta: primary_object.title, at: primary_object.created_at }

    if (generated_at = parsed_workspace_time(theater_brief_payload&.dig(:generated_at)))
      entries << { kind: "brief", title: "Stored theater brief refreshed", meta: primary_object.title, at: generated_at }
    end

    @case_notes.first(6).each do |note|
      entries << {
        kind: note.kind,
        title: note.body.to_s.tr("\n", " ").squish.truncate(120),
        meta: note.user.email,
        at: note.created_at,
      }
    end

    entries.sort_by { |entry| entry[:at] || Time.zone.at(0) }.reverse.first(8)
  end

  def parsed_workspace_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def normalized_return_to
    value = params[:return_to].to_s
    return nil if value.blank?
    return nil unless value.start_with?("/") && !value.start_with?("//")

    value
  end

  def default_case_title(source_object)
    return "New case" if source_object[:title].blank?

    "Investigate #{source_object[:title]}"
  end

  def default_case_severity(source_object)
    source_context = source_object[:source_context] || {}
    severity = source_context["severity"] || source_context[:severity]
    return severity if InvestigationCase::SEVERITIES.include?(severity)

    "medium"
  end
end
