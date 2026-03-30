class AreaBriefService
  STATE_LABELS = {
    closed: "Closed / Denied Transit",
    restricted_selective: "Restricted / Selective Passage",
    restricted: "Restricted Transit",
    reopening: "Partial Reopening",
    open: "Open Transit",
    live_monitor: "Live Monitor",
  }.freeze

  STATE_CONFIDENCE = {
    closed: "high",
    restricted_selective: "medium-high",
    restricted: "medium",
    reopening: "medium",
    open: "low-medium",
    live_monitor: "low",
  }.freeze

  STATE_PRIORITY = {
    restricted_selective: 0,
    closed: 1,
    restricted: 2,
    reopening: 3,
    open: 4,
    live_monitor: 5,
  }.freeze

  def initialize(area_workspace, bounds:)
    @area_workspace = area_workspace
    @bounds = bounds
  end

  def call
    return maritime_brief if maritime_area?

    generic_brief
  end

  private

  def maritime_brief
    area_article_candidates.enqueue_hydration!

    evidence = maritime_evidence
    return generic_brief if evidence.empty?

    state = selected_state_for(evidence)
    {
      title: "Assessment",
      status: state.to_s,
      status_label: STATE_LABELS.fetch(state),
      confidence: STATE_CONFIDENCE.fetch(state),
      summary: maritime_summary_for(state, evidence),
      evidence: evidence_for_display(evidence, state),
      watch_items: maritime_watch_items(state),
    }
  end

  def generic_brief
    {
      title: "Assessment",
      status: "live_monitor",
      status_label: STATE_LABELS.fetch(:live_monitor),
      confidence: STATE_CONFIDENCE.fetch(:live_monitor),
      summary: generic_summary,
      evidence: generic_evidence,
      watch_items: generic_watch_items,
    }
  end

  def maritime_evidence
    area_article_candidates.call.filter_map do |candidate|
      event = candidate[:event]
      signal = maritime_signal_for(event)
      state = signal&.fetch(:state, nil)
      next unless state

      {
        title: event.title.presence || event.name,
        publisher: publisher_for(event),
        published_at: event.published_at,
        url: event.url,
        summary: signal[:excerpt].presence || excerpt_for(candidate[:text]),
        source_kind: event.news_source&.source_kind.to_s,
        state: state,
        signals: signal[:signals],
        score: maritime_score_for(candidate, state),
      }
    end.sort_by { |item| [state_rank(item[:state]), -item[:score], -(item[:published_at]&.to_i || 0)] }
  end

  def selected_state_for(evidence)
    grouped = evidence.group_by { |item| item[:state] }
    recent_selective = grouped.fetch(:restricted_selective, []).any? do |item|
      item[:published_at].present? && item[:published_at] > 24.hours.ago
    end

    return :restricted_selective if recent_selective
    return :closed if grouped[:closed].to_a.sum { |item| item[:score] } >= 1.6
    return :restricted if grouped[:restricted].present?
    return :reopening if grouped[:reopening].present?
    return :open if grouped[:open].present?

    :live_monitor
  end

  def maritime_summary_for(state, evidence)
    mixed = evidence.map { |item| item[:state] }.uniq.size > 1

    case state
    when :closed
      "Passage through #{@area_workspace.name} appears effectively denied rather than normally open. Recent reporting includes references to blocked transit or explicit warnings that vessels are not allowed through the corridor."
    when :restricted_selective
      summary = "Passage through #{@area_workspace.name} does not look fully open. Recent reporting points to selective, permission-based transit and toll-like monetization measures, with some traffic rerouted north instead of moving under normal free passage."
      mixed ? "#{summary} Signals are mixed, but the stronger current pattern is constrained passage rather than normal open transit." : summary
    when :restricted
      "Traffic through #{@area_workspace.name} is moving under constrained conditions rather than normal transit. Recent reporting points to rerouting, congestion, or war-risk frictions that materially degrade the corridor."
    when :reopening
      "Transit through #{@area_workspace.name} appears to be resuming in limited pockets, but the corridor still reads as contested rather than fully normalized. Reopening language is present, though it sits alongside disruption reporting."
    when :open
      "Recent reporting suggests ships are still transiting #{@area_workspace.name}, but confidence in a fully normal operating picture is limited. The corridor should be treated as a live watch area rather than definitively resolved."
    else
      generic_summary
    end
  end

  def generic_summary
    signals = area_article_candidates.call.first(6)
    return "This area is saved and live, but it does not yet have enough structured signal to support a higher-confidence assessment." if signals.empty?

    "This area has live reporting and movement data, but the page still needs stronger ranking and change analysis before it can support a high-trust operational readout."
  end

  def evidence_for_display(evidence, selected_state)
    preferred = evidence.select { |item| item[:state] == selected_state }
    fallback = evidence.reject { |item| item[:state] == selected_state }
    ordered = preferred.size >= 2 ? preferred : (preferred + fallback)

    ordered
      .uniq { |item| item[:url].presence || [item[:title], item[:publisher], item[:published_at]] }
      .first(4)
      .map do |item|
        {
          title: item[:title],
          publisher: item[:publisher],
          published_at: item[:published_at],
          url: item[:url],
        }
      end
  end

  def generic_evidence
    area_article_candidates.call.first(4).map do |candidate|
      event = candidate[:event]
      {
        title: event.title.presence || event.name,
        publisher: publisher_for(event),
        published_at: event.published_at,
        url: event.url,
      }
    end
  end

  def maritime_watch_items(state)
    items = [
      "Vessel clustering near the narrows and any north-corridor diversion pattern",
      "Transit-fee, toll, or permission-based reporting from higher-trust sources",
      "GPS jamming, mine-clearance activity, and materially restrictive NOTAMs",
    ]
    items << "Any confirmed passage-denial language from state or naval mission sources" if state == :closed
    items
  end

  def generic_watch_items
    [
      "What changed in the last 6 to 24 hours",
      "Which signals are corroborated by more than one source",
      "Which objects or assets need to be pinned for follow-up",
    ]
  end

  def area_article_candidates
    @area_article_candidates ||= AreaArticleCandidateService.new(@area_workspace, bounds: @bounds)
  end

  def maritime_area?
    @area_workspace.profile == "maritime" ||
      area_article_candidates.area_terms.any? { |term| term.include?("hormuz") || term.include?("mandeb") || term.include?("suez") }
  end

  def maritime_signal_for(event)
    article = event.news_article
    persisted_signal = normalize_signal(article&.metadata.to_h["maritime_passage_signal"])
    return persisted_signal if persisted_signal.present?

    normalize_signal(
      MaritimePassageSignalExtractor.extract(
        title: event.title.presence || article&.title,
        summary: article&.summary
      )
    )
  end

  def normalize_signal(signal)
    return nil unless signal.respond_to?(:[])

    state = value_for(signal, :state).presence
    return nil if state.blank?

    {
      state: state.to_sym,
      signals: Array(value_for(signal, :signals)).map(&:to_s),
      excerpt: clean_text(value_for(signal, :excerpt)).presence,
    }
  end

  def maritime_score_for(candidate, state)
    candidate[:score].to_f + (0.1 * (5 - state_rank(state)))
  end

  def state_rank(state)
    STATE_PRIORITY.fetch(state, 99)
  end

  def publisher_for(event)
    event.news_source&.name.presence || event.source.presence || event.name
  end

  def value_for(obj, key)
    return unless obj.respond_to?(:[])

    obj[key] || obj[key.to_s]
  end

  def clean_text(value)
    ActionController::Base.helpers.strip_tags(value.to_s).squish
  end

  def excerpt_for(text)
    clean_text(text).first(280)
  end
end
