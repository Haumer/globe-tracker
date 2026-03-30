class AreaBriefService
  SOURCE_WEIGHTS = {
    "wire" => 1.0,
    "publisher" => 0.78,
    "aggregator" => 0.42,
    "platform" => 0.25,
  }.freeze

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

  PASSAGE_PATTERNS = {
    closed: [
      /no ship is allowed to pass/i,
      /not allowed to pass/i,
      /\b(?:blockade|blocked|blocking)\b/i,
      /\b(?:closed|closure)\b/i,
      /effective closure/i,
      /near halt/i,
      /\bmined?\b/i,
    ],
    restricted_selective: [
      /\btransit fees?\b/i,
      /\btolls?\b/i,
      /\bmonetiz(?:e|es|ed|ing)\b/i,
      /\bpermission\b/i,
      /\ballow(?:ed|s)? \d+ (?:more )?(?:ships?|tankers?|vessels?)\b/i,
      /\bselective(?:ly)?\b/i,
      /\bcalling the shots\b/i,
    ],
    restricted: [
      /\brerout(?:e|ed|ing)\b/i,
      /\bnorth(?:ern)? corridor\b/i,
      /\bcongestion\b/i,
      /\bcrowding\b/i,
      /\bwar lev(?:y|ies)\b/i,
      /insurance cover cuts?/i,
      /\bdisrupt(?:ed|ion|ing)\b/i,
      /\brestricted\b/i,
      /\bcontrol of the strait\b/i,
    ],
    reopening: [
      /\breopen(?:ed|ing)?\b/i,
      /\bresume(?:d|s|ing)?\b/i,
      /\bquestion of time\b/i,
      /\bone way or another\b/i,
    ],
    open: [
      /\bclear(?:ed)? .* safely\b/i,
      /\bpassed safely\b/i,
      /\bsafely transited\b/i,
      /\bopen\b/i,
    ],
  }.freeze

  TERM_ALIASES = {
    /hormuz/i => ["hormuz", "strait of hormuz"],
    /bab el[- ]mandeb|bab al[- ]mandab/i => ["bab el-mandeb", "bab al-mandab", "red sea chokepoint"],
    /bosporus/i => ["bosporus", "bosphorus"],
    /suez/i => ["suez canal", "suez"],
    /malacca/i => ["strait of malacca", "malacca"],
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
    candidate_events.filter_map do |event|
      text = clean_text([event.title, event.news_article&.summary].compact.join(" "))
      next if text.blank?

      state = classify_passage_state(text)
      next unless state

      {
        title: event.title.presence || event.name,
        publisher: event.news_source&.name.presence || event.source.presence || event.name,
        published_at: event.published_at,
        url: event.url,
        summary: excerpt_for(text),
        source_kind: event.news_source&.source_kind.to_s,
        state: state,
        score: score_for(event, state),
      }
    end.sort_by { |item| [state_rank(item[:state]), -item[:score], -(item[:published_at]&.to_i || 0)] }
  end

  def selected_state_for(evidence)
    grouped = evidence.group_by { |item| item[:state] }
    recent_selective = grouped.fetch(:restricted_selective, []).any? { |item| item[:published_at].present? && item[:published_at] > 24.hours.ago }

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
    signals = scoped_news_scope.limit(6)
    return "This area is saved and live, but it does not yet have enough structured signal to support a higher-confidence assessment." if signals.empty?

    "This area has live reporting and movement data, but the page still needs stronger ranking and change analysis before it can support a high-trust operational readout."
  end

  def evidence_for_display(evidence, selected_state)
    preferred = evidence.select { |item| item[:state] == selected_state }
    fallback = evidence.reject { |item| item[:state] == selected_state }

    (preferred + fallback)
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
    scoped_news_scope.limit(4).map do |event|
      {
        title: event.title.presence || event.name,
        publisher: event.news_source&.name.presence || event.source.presence || event.name,
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

  def candidate_events
    @candidate_events ||= begin
      merged = {}
      scoped_news_scope.each { |event| merged[event.id] = event }
      named_news_scope.each { |event| merged[event.id] = event }
      merged.values.sort_by { |event| -(event.published_at&.to_i || 0) }
    end
  end

  def scoped_news_scope
    @scoped_news_scope ||= NewsEvent
      .within_bounds(@bounds)
      .where("published_at > ?", 36.hours.ago)
      .where.not(content_scope: "out_of_scope")
      .includes(:news_article, :news_source)
      .order(published_at: :desc)
      .limit(24)
  end

  def named_news_scope
    return NewsEvent.none if area_terms.empty?

    fragments = []
    bindings = {}
    area_terms.each_with_index do |term, index|
      key = :"term_#{index}"
      bindings[key] = "%#{term.downcase}%"
      fragments << "(lower(news_events.title) LIKE :#{key} OR lower(coalesce(news_articles.summary, '')) LIKE :#{key})"
    end

    NewsEvent
      .left_outer_joins(:news_article)
      .where("news_events.published_at > ?", 48.hours.ago)
      .where.not(content_scope: "out_of_scope")
      .where(fragments.join(" OR "), bindings)
      .includes(:news_article, :news_source)
      .order(published_at: :desc)
      .limit(24)
  end

  def area_terms
    @area_terms ||= begin
      base_terms = [@area_workspace.name, @area_workspace.region_name].compact.map { |value| clean_text(value).downcase }.reject(&:blank?)
      alias_terms = TERM_ALIASES.each_with_object([]) do |(matcher, terms), memo|
        memo.concat(terms) if base_terms.any? { |value| value.match?(matcher) }
      end

      (base_terms + alias_terms).uniq
    end
  end

  def maritime_area?
    @area_workspace.profile == "maritime" || area_terms.any? { |term| term.include?("hormuz") || term.include?("mandeb") || term.include?("suez") }
  end

  def classify_passage_state(text)
    PASSAGE_PATTERNS.each do |state, patterns|
      return state if patterns.any? { |pattern| text.match?(pattern) }
    end

    nil
  end

  def score_for(event, state)
    recency_bonus = if event.published_at.present?
      if event.published_at > 6.hours.ago
        0.4
      elsif event.published_at > 24.hours.ago
        0.2
      else
        0.0
      end
    else
      0.0
    end

    hydration_bonus = event.news_article&.hydration_status == "hydrated" ? 0.15 : 0.0
    source_weight = SOURCE_WEIGHTS.fetch(event.news_source&.source_kind.to_s, 0.5)
    source_weight + recency_bonus + hydration_bonus + (0.1 * (5 - state_rank(state)))
  end

  def state_rank(state)
    case state
    when :closed then 0
    when :restricted_selective then 1
    when :restricted then 2
    when :reopening then 3
    when :open then 4
    else 5
    end
  end

  def clean_text(value)
    ActionController::Base.helpers.strip_tags(value.to_s).squish
  end

  def excerpt_for(text)
    clean_text(text).first(280)
  end
end
