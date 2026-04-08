class MaritimePassageSignalExtractor
  SIGNAL_DEFINITIONS = [
    { key: "transit_fee", state: :restricted_selective, regex: /\btransit fees?\b/i },
    { key: "tolling", state: :restricted_selective, regex: /\btolls?\b/i },
    { key: "monetized_passage", state: :restricted_selective, regex: /\bmonetiz(?:e|es|ed|ing)\b/i },
    { key: "permission_required", state: :restricted_selective, regex: /\bpermission(?:-based)?\b/i },
    { key: "selective_passage", state: :restricted_selective, regex: /\bselective(?:ly)?\b/i },
    { key: "limited_ship_allowance", state: :restricted_selective, regex: /\ballow(?:ed|s)? \d+ (?:more )?(?:ships?|tankers?|vessels?)\b/i },
    { key: "rerouting", state: :restricted, regex: /\brerout(?:e|ed|ing)\b/i },
    { key: "north_corridor", state: :restricted, regex: /\bnorth(?:ern)? corridor\b/i },
    { key: "congestion", state: :restricted, regex: /\bcongestion\b|\bcrowding\b/i },
    { key: "war_levy", state: :restricted, regex: /\bwar lev(?:y|ies)\b/i },
    { key: "insurance_disruption", state: :restricted, regex: /insurance cover cuts?|war-risk premiums?/i },
    { key: "closed", state: :closed, regex: /\b(?:closed|closure)\b/i },
    { key: "blocked", state: :closed, regex: /\b(?:blockade|blocked|blocking)\b/i },
    { key: "denied_transit", state: :closed, regex: /no ship is allowed to pass|not allowed to pass/i },
    { key: "mine_risk", state: :closed, regex: /\bmined?\b|mine-clearance/i },
    { key: "reopening", state: :reopening, regex: /\breopen(?:ed|ing)?\b|\bresume(?:d|s|ing)?\b/i },
    { key: "safe_passage", state: :open, regex: /\bsafe passage\b|\bsafe transit\b/i },
    { key: "open_transit", state: :open, regex: /\bopen(?:ed|ing)? (?:to|for) (?:ships?|tankers?|vessels?|shipping|transit)\b/i },
    { key: "safe_transit", state: :open, regex: /\bclear(?:ed)? .* safely\b|\bsafely transited\b|\bpassed safely\b/i },
  ].freeze

  STATE_PRIORITY = {
    restricted_selective: 0,
    closed: 1,
    restricted: 2,
    reopening: 3,
    open: 4,
  }.freeze

  class << self
    def extract(title:, summary:)
      new(title: title, summary: summary).extract
    end
  end

  def initialize(title:, summary:)
    @title = title.to_s
    @summary = summary.to_s
  end

  def extract
    text = normalized_text
    return nil if text.blank?

    matches = SIGNAL_DEFINITIONS.filter_map do |definition|
      next unless text.match?(definition[:regex])

      definition.slice(:key, :state)
    end
    return nil if matches.empty?

    {
      state: selected_state(matches),
      signals: matches.map { |item| item[:key] }.uniq,
      states: matches.map { |item| item[:state].to_s }.uniq,
      excerpt: text.first(280),
    }
  end

  private

  def selected_state(matches)
    matches
      .map { |item| item[:state] }
      .uniq
      .sort_by { |state| STATE_PRIORITY.fetch(state, 99) }
      .first
  end

  def normalized_text
    ActionController::Base.helpers.strip_tags([@title, @summary].compact.join(" ")).squish
  end
end
