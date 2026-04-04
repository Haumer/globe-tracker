class AreaImpactAssessmentService
  DOMAIN_LABELS = {
    "military_posture" => "Military Posture",
    "maritime_passage" => "Maritime Passage",
    "infrastructure_exposure" => "Infrastructure Exposure",
    "market_pressure" => "Market Pressure",
  }.freeze

  LINKED_DOMAINS = {
    "military_posture" => %w[maritime_passage infrastructure_exposure market_pressure],
    "maritime_passage" => %w[military_posture infrastructure_exposure market_pressure],
    "infrastructure_exposure" => %w[military_posture maritime_passage market_pressure],
    "market_pressure" => %w[military_posture maritime_passage infrastructure_exposure],
  }.freeze

  MILITARY_EVENT_TYPES = %w[ground_operation airstrike missile_attack].freeze
  MILITARY_KEYWORDS = /\b(troops?|soldiers?|marines?|airborne|brigade|battalion|deployment|deploy(?:s|ed|ing)?|reinforcements?|staging|mobiliz(?:e|ation)|airlift|offensive|raid|strike|missiles?|drones?|naval)\b/i
  MARITIME_KEYWORDS = /\b(ships?|vessels?|tankers?|shipping|maritime|transit|passage|chokepoint|corridor|narrows?|rerout(?:e|ing)|convoy|port|strait|canal|fee|fees|toll|tolls)\b/i
  INFRASTRUCTURE_KEYWORDS = /\b(refiner(?:y|ies)|terminal(?:s)?|port(?:s)?|pipeline(?:s)?|power plant(?:s)?|airport(?:s)?|airbase(?:s)?|base(?:s)?|export(?:s| terminals?)|grid|facility|facilities|island(?:s)?)\b/i
  MARKET_KEYWORDS = /\b(oil|brent|wti|lng|gas|energy|insurance|freight|premium|premiums|market|markets|prices?|exports?)\b/i

  def initialize(area_workspace, bounds:, movement:, assets:, chokepoints:, situations:, insights:)
    @area_workspace = area_workspace
    @bounds = bounds
    @movement = movement.with_indifferent_access
    @assets = assets.with_indifferent_access
    @chokepoints = Array(chokepoints)
    @situations = Array(situations)
    @insights = Array(insights)
  end

  def call
    military = build_military_posture_impact
    maritime = build_maritime_passage_impact(military)
    infrastructure = build_infrastructure_exposure_impact(military, maritime)
    market = build_market_pressure_impact(military, maritime, infrastructure)

    link_impacts!([military, maritime, infrastructure, market].compact)
  end

  private

  def build_military_posture_impact
    score = 0.0
    score += 2.2 if military_candidates.any?
    score += 0.8 if troop_reinforcement_candidates.any?
    score += 0.9 if @movement[:flights_military].to_i >= 3
    score += 0.7 if @movement[:notams_total].to_i >= 6
    score += 0.6 if @assets[:military_bases].to_i.positive?
    score += 0.5 if @situations.any? || @insights.any?

    return if score < 2.0

    lead = troop_reinforcement_candidates.first || military_candidates.first
    {
      domain: "military_posture",
      title: DOMAIN_LABELS.fetch("military_posture"),
      severity: severity_for(score),
      summary: military_summary_for(lead),
      linked_domains: [],
      metrics: [
        metric("Military flights", @movement[:flights_military]),
        metric("Active NOTAMs", @movement[:notams_total]),
        metric("Military bases", @assets[:military_bases]),
        metric("Situations", @situations.size),
      ],
      evidence: evidence_for(troop_reinforcement_candidates.presence || military_candidates),
    }
  end

  def build_maritime_passage_impact(military_impact)
    score = 0.0
    score += 1.6 if @chokepoints.any?
    score += 1.2 if maritime_candidates.any?
    score += 0.9 if military_impact
    score += 0.8 if stressed_chokepoints.any?
    score += 0.6 if @movement[:ships_total].to_i >= 6
    score += 0.4 if @movement[:notams_total].to_i >= 6

    return if score < 2.0

    lead_chokepoint = stressed_chokepoints.first || @chokepoints.first
    {
      domain: "maritime_passage",
      title: DOMAIN_LABELS.fetch("maritime_passage"),
      severity: severity_for(score),
      summary: maritime_summary_for(lead_chokepoint, military_impact: military_impact),
      linked_domains: [],
      metrics: [
        metric("Chokepoints in scope", @chokepoints.size),
        metric("Ships in area", @movement[:ships_total]),
        metric("Nearby ships", ships_nearby_total_for(lead_chokepoint)),
        metric("Status", status_label_for(value_for(lead_chokepoint, :status))),
      ],
      evidence: evidence_for(maritime_candidates.presence || military_candidates),
    }
  end

  def build_infrastructure_exposure_impact(military_impact, maritime_impact)
    total_assets = @assets[:airports].to_i + @assets[:military_bases].to_i + @assets[:power_plants].to_i + @assets[:chokepoints].to_i
    score = 0.0
    score += 0.8 if total_assets.positive?
    score += 1.1 if military_impact
    score += 0.7 if maritime_impact
    score += 0.8 if infrastructure_candidates.any?
    score += 0.5 if @situations.any?
    score += 0.5 if @assets[:power_plants].to_i.positive?
    score += 0.4 if @assets[:airports].to_i.positive?

    return if score < 2.0

    {
      domain: "infrastructure_exposure",
      title: DOMAIN_LABELS.fetch("infrastructure_exposure"),
      severity: severity_for(score),
      summary: infrastructure_summary_for,
      linked_domains: [],
      metrics: [
        metric("Power plants", @assets[:power_plants]),
        metric("Airports", @assets[:airports]),
        metric("Military bases", @assets[:military_bases]),
        metric("Chokepoints", @assets[:chokepoints]),
      ],
      evidence: evidence_for(infrastructure_candidates.presence || military_candidates.presence || maritime_candidates),
    }
  end

  def build_market_pressure_impact(military_impact, maritime_impact, infrastructure_impact)
    score = 0.0
    score += 1.6 if market_chokepoints.any?
    score += 1.0 if military_impact
    score += 1.0 if maritime_impact
    score += 0.6 if infrastructure_impact
    score += 0.8 if strongest_market_move.to_f.abs >= 2.0
    score += 0.6 if strongest_flow_exposure.to_i >= 10
    score += 0.5 if market_candidates.any?

    return if score < 2.2

    {
      domain: "market_pressure",
      title: DOMAIN_LABELS.fetch("market_pressure"),
      severity: severity_for(score),
      summary: market_summary_for,
      linked_domains: [],
      metrics: [
        metric("Benchmarks", benchmark_labels.presence || "None"),
        metric("Largest move", largest_move_label),
        metric("Flow exposure", flow_exposure_label),
        metric("Market-linked chokepoints", market_chokepoints.size),
      ],
      evidence: evidence_for(market_candidates.presence || maritime_candidates.presence || military_candidates),
    }
  end

  def military_summary_for(candidate)
    if candidate
      "Recent reporting tied to #{@area_workspace.name} points to force reinforcement or combat activity, and it is not isolated to a single headline. The area also shows #{@movement[:flights_military].to_i} military flights, #{@movement[:notams_total].to_i} active NOTAMs, and #{@assets[:military_bases].to_i} military bases in scope."
    else
      "Movement and conflict indicators in #{@area_workspace.name} suggest elevated force posture rather than routine background traffic. This should be treated as an area-wide posture change, not a standalone signal."
    end
  end

  def maritime_summary_for(chokepoint, military_impact:)
    chokepoint_name = value_for(chokepoint, :name).presence || "the local corridor"

    if maritime_candidates.any?
      "Passage through #{chokepoint_name} should be treated as a live risk rather than routine maritime flow. Reporting inside #{@area_workspace.name} points to shipping friction, and the surrounding posture picture increases the chance that passage conditions tighten next."
    elsif military_impact
      "Military posture changes in #{@area_workspace.name} have a direct maritime read-through because #{chokepoint_name} sits inside the workspace. Even without a confirmed closure, troop or strike reporting can quickly translate into rerouting, convoying, or selective passage."
    else
      "This area contains #{chokepoint_name}, so any local escalation can propagate into maritime passage conditions quickly. Treat the corridor as exposed even when disruption is still emerging rather than fully visible."
    end
  end

  def infrastructure_summary_for
    exposed_assets = []
    exposed_assets << "#{@assets[:power_plants].to_i} power plants" if @assets[:power_plants].to_i.positive?
    exposed_assets << "#{@assets[:airports].to_i} airports" if @assets[:airports].to_i.positive?
    exposed_assets << "#{@assets[:military_bases].to_i} military bases" if @assets[:military_bases].to_i.positive?
    exposed_assets << "#{@assets[:chokepoints].to_i} chokepoints" if @assets[:chokepoints].to_i.positive?

    "Escalation in #{@area_workspace.name} sits close to #{exposed_assets.to_sentence.presence || 'multiple monitored assets'}. The next-order effect may be disruption to staging bases, transport nodes, power, or export infrastructure rather than a story that stays confined to one article."
  end

  def market_summary_for
    chokepoint_names = market_chokepoints.map { |point| value_for(point, :name) }.compact.first(2)
    benchmarks = benchmark_labels

    "#{chokepoint_names.to_sentence.presence || @area_workspace.name} links this workspace directly to #{benchmarks.presence || 'energy and freight benchmarks'}. When military or passage risk rises here, the effect is not just local: it should be watched for pressure on export flows, insurance, and benchmark pricing."
  end

  def link_impacts!(impacts)
    present_domains = impacts.map { |impact| impact[:domain] }

    impacts.each do |impact|
      linked = LINKED_DOMAINS.fetch(impact[:domain], []).select { |domain| present_domains.include?(domain) }
      impact[:linked_domains] = linked.map { |domain| DOMAIN_LABELS.fetch(domain) }
    end

    impacts
  end

  def severity_for(score)
    return "critical" if score >= 4.6
    return "high" if score >= 3.2
    return "medium" if score >= 2.2

    "low"
  end

  def area_article_candidates
    @area_article_candidates ||= AreaArticleCandidateService.new(@area_workspace, bounds: @bounds)
  end

  def candidates
    @candidates ||= area_article_candidates.call.map do |candidate|
      candidate.merge(primary_claim: primary_claim_for(candidate[:event]))
    end
  end

  def military_candidates
    @military_candidates ||= candidates.select do |candidate|
      claim = candidate[:primary_claim]
      military_claim?(claim) || combined_text(candidate).match?(MILITARY_KEYWORDS)
    end
  end

  def troop_reinforcement_candidates
    @troop_reinforcement_candidates ||= candidates.select do |candidate|
      combined_text(candidate).match?(/\b(troops?|soldiers?|marines?|airborne|brigade|battalion|reinforcements?|deployed?|deployment|airlift)\b/i)
    end
  end

  def maritime_candidates
    @maritime_candidates ||= candidates.select do |candidate|
      maritime_signal_present?(candidate[:event]) || combined_text(candidate).match?(MARITIME_KEYWORDS)
    end
  end

  def infrastructure_candidates
    @infrastructure_candidates ||= candidates.select do |candidate|
      claim = candidate[:primary_claim]
      infrastructure_claim?(claim) || combined_text(candidate).match?(INFRASTRUCTURE_KEYWORDS)
    end
  end

  def market_candidates
    @market_candidates ||= candidates.select do |candidate|
      combined_text(candidate).match?(MARKET_KEYWORDS)
    end
  end

  def market_chokepoints
    @market_chokepoints ||= @chokepoints.select { |point| commodity_signals_for(point).any? }
  end

  def stressed_chokepoints
    @stressed_chokepoints ||= @chokepoints.select do |point|
      %w[critical elevated restricted restricted_selective closed].include?(value_for(point, :status).to_s)
    end
  end

  def primary_claim_for(event)
    claims = event.news_article&.news_claims.to_a
    claims&.find(&:primary) || claims&.first
  end

  def military_claim?(claim)
    return false unless claim

    claim.event_family == "conflict" && MILITARY_EVENT_TYPES.include?(claim.event_type)
  end

  def infrastructure_claim?(claim)
    return false unless claim

    claim.event_family == "infrastructure" || claim.event_family == "transport"
  end

  def maritime_signal_present?(event)
    signal = event.news_article&.metadata.to_h["maritime_passage_signal"]
    value_for(signal, :state).present?
  end

  def evidence_for(selected_candidates, limit: 3)
    Array(selected_candidates)
      .compact
      .uniq { |candidate| candidate[:event].id }
      .sort_by { |candidate| [-candidate[:score].to_f, -(candidate[:event].published_at&.to_i || 0)] }
      .first(limit)
      .map do |candidate|
        event = candidate[:event]
        {
          title: event.title.presence || event.name,
          publisher: event.news_source&.name.presence || event.source.presence || event.name,
          published_at: event.published_at,
          url: event.url,
        }
      end
  end

  def commodity_signals_for(chokepoint)
    Array(value_for(chokepoint, :commodity_signals))
  end

  def strongest_market_move
    commodity_signals = market_chokepoints.flat_map { |point| commodity_signals_for(point) }
    commodity_signals.map { |signal| value_for(signal, :change_pct).to_f.abs }.max
  end

  def strongest_flow_exposure
    commodity_signals = market_chokepoints.flat_map { |point| commodity_signals_for(point) }
    commodity_signals.map { |signal| value_for(signal, :flow_pct).to_i }.max
  end

  def benchmark_labels
    market_chokepoints
      .flat_map { |point| commodity_signals_for(point) }
      .map { |signal| value_for(signal, :name).presence || value_for(signal, :symbol).to_s }
      .reject(&:blank?)
      .uniq
      .first(4)
      .join(", ")
  end

  def largest_move_label
    commodity_signals = market_chokepoints.flat_map { |point| commodity_signals_for(point) }
    strongest = commodity_signals.max_by { |signal| value_for(signal, :change_pct).to_f.abs }
    return "None" unless strongest

    label = value_for(strongest, :name).presence || value_for(strongest, :symbol)
    change_pct = value_for(strongest, :change_pct).to_f
    "#{label} #{format('%+.2f%%', change_pct)}"
  end

  def flow_exposure_label
    exposure = strongest_flow_exposure
    return "Not available" unless exposure.to_i.positive?

    "#{exposure.to_i}% linked flow"
  end

  def ships_nearby_total_for(chokepoint)
    value_for(value_for(chokepoint, :ships_nearby), :total).to_i
  end

  def metric(label, value)
    { label: label, value: value.presence || value.to_s.presence || "0" }
  end

  def status_label_for(status)
    status.to_s.tr("_", " ").presence&.titleize || "Unknown"
  end

  def combined_text(candidate)
    @combined_text ||= {}
    @combined_text[candidate[:event].id] ||= [
      candidate[:text],
      candidate[:primary_claim]&.claim_text,
      candidate[:event].title,
      candidate[:event].news_article&.summary,
    ].compact.join(" ").downcase
  end

  def value_for(obj, key)
    return unless obj.respond_to?(:[])

    obj[key] || obj[key.to_s]
  end
end
