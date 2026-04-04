class InvestigationCasesController < ApplicationController
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
    supporting_signals = case_workspace_supporting_signals(primary_object)
    resource_profile = ResourceProfileService.call(primary_object: primary_object)

    {
      primary_object: primary_object,
      node_context: node_context,
      source_context: source_context,
      assessment: case_workspace_assessment(primary_object, source_context, theater_brief_payload),
      why_we_believe_it: case_workspace_why_we_believe_it(primary_object, source_context, theater_brief_payload),
      key_developments: case_workspace_key_developments(primary_object, node_context, theater_brief_payload),
      watch_next: case_workspace_watch_next(primary_object, source_context, theater_brief_payload),
      metrics: case_workspace_metrics(primary_object, source_context, node_context),
      supporting_signals: supporting_signals,
      resource_profile: resource_profile,
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

  def case_workspace_supporting_signals(primary_object)
    NearbySupportingSignalsService.call(
      object_kind: primary_object.object_kind,
      latitude: primary_object.latitude,
      longitude: primary_object.longitude
    )
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
