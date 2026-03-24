class NewsClaimExtractor
  EVENT_RULES = [
    {
      event_family: "conflict",
      event_type: "ceasefire",
      strategy: :subject_participants,
      regex: /\b(ceasefire|truce|halt in fighting|halt-fire)\b/i,
    },
    {
      event_family: "diplomacy",
      event_type: "summit",
      strategy: :participants,
      regex: /\b(summit|summits|leader(?:s)? meeting|high-level meeting)\b/i,
    },
    {
      event_family: "diplomacy",
      event_type: "negotiation",
      strategy: :participants,
      regex: /\b(talks?|negotiat(?:e|es|ed|ing|ion|ions)|dialogue|discussions?|peace talks?|truce talks?)\b/i,
    },
    {
      event_family: "diplomacy",
      event_type: "agreement",
      strategy: :participants,
      regex: /\b(agreement|agreements|pact|pacts|deal|deals|accord|accords|memorandum|mou|finalis(?:e|es|ed|ing))\b/i,
    },
    {
      event_family: "diplomacy",
      event_type: "official_visit",
      strategy: :participants,
      regex: /\b(visits?|visited|visit to|arrives? in|trip to)\b/i,
    },
    {
      event_family: "diplomacy",
      event_type: "diplomatic_contact",
      strategy: :participants,
      regex: /\b(speaks? to|spoke to|calls?|called|telephoned|phone call)\b/i,
    },
    {
      event_family: "economy",
      event_type: "sanction_action",
      strategy: :directional,
      regex: /\b(sanctions?|blacklists?|embargo(?:es|ed)?|ban(?:s|ned)?|waiver(?:s)?)\b/i,
    },
    {
      event_family: "economy",
      event_type: "trade_measure",
      strategy: :directional,
      regex: /\b(tariffs?|duties|trade curbs?|export controls?)\b/i,
    },
    {
      event_family: "conflict",
      event_type: "airstrike",
      strategy: :directional,
      regex: /\b(airstrikes?|bombard(?:s|ed)?|bombings?|bombs?|air raids?)\b/i,
    },
    {
      event_family: "conflict",
      event_type: "missile_attack",
      strategy: :directional,
      regex: /\b(missiles?\s+(?:hit|hits|strike|strikes)|rockets?\s+(?:hit|hits|strike|strikes)|drones?\s+(?:hit|hits|strike|strikes)|launches?\s+(?:missiles?|drones?|rockets?)|fires?\s+(?:at|on|into|against))\b/i,
    },
    {
      event_family: "conflict",
      event_type: "ground_operation",
      strategy: :directional,
      regex: /\b(strikes?|attacks?|shells?|target(?:s|ed|ing)?|invades?|raids?|troops|offensive|offensives|clashes?|fighting|ground assault|deploy(?:s|ed|ing)?)\b/i,
    },
    {
      event_family: "cyber",
      event_type: "cyberattack",
      strategy: :directional,
      regex: /\b(cyberattacks?|cyber attack|hack(?:er|ers|s|ed|ing)?|breach(?:es|ed)?|ransomware)\b/i,
    },
    {
      event_family: "infrastructure",
      event_type: "outage",
      strategy: :subject,
      regex: /\b(outages?|blackouts?|power cuts?|internet shutdowns?|service disruptions?|network failures?)\b/i,
    },
    {
      event_family: "security",
      event_type: "explosion",
      strategy: :subject,
      regex: /\b(explosion|explosions|blast|blasts)\b/i,
    },
    {
      event_family: "transport",
      event_type: "crash",
      strategy: :subject,
      regex: /\b(crashes?|crashed|collision|collides?|collided)\b/i,
    },
    {
      event_family: "politics",
      event_type: "election",
      strategy: :subject,
      regex: /\b(election|elections|vote|votes|voting|polls?)\b/i,
    },
    {
      event_family: "politics",
      event_type: "protest",
      strategy: :subject,
      regex: /\b(protests?|demonstrations?|rallies?|marches?)\b/i,
    },
    {
      event_family: "justice",
      event_type: "arrest_detention",
      strategy: :directional,
      regex: /\b(arrests?|detains?|detained|detention|jails?|sentences?)\b/i,
    },
    {
      event_family: "humanitarian",
      event_type: "aid_delivery",
      strategy: :provider_recipient,
      regex: /\b(aid|supports?|backs?|sends?|delivers?|airlifts?)\b/i,
    },
    {
      event_family: "disaster",
      event_type: "earthquake",
      strategy: :subject,
      regex: /\b(earthquake|earthquakes|aftershock|aftershocks)\b/i,
    },
    {
      event_family: "disaster",
      event_type: "flood",
      strategy: :subject,
      regex: /\b(flood|floods|flooding)\b/i,
    },
    {
      event_family: "disaster",
      event_type: "wildfire",
      strategy: :subject,
      regex: /\b(wildfire|wildfires|bushfire|bushfires)\b/i,
    },
    {
      event_family: "disaster",
      event_type: "storm",
      strategy: :subject,
      regex: /\b(hurricane|hurricanes|typhoon|typhoons|storm|storms|cyclone|cyclones)\b/i,
    },
    {
      event_family: "information",
      event_type: "accusation_statement",
      strategy: :claimant_target,
      regex: /\b(accuses?|blames?|denies?|warns?|claims?|says?|vows?|threatens?)\b/i,
    },
  ].freeze

  STATE_ALIAS_OVERRIDES = {
    "us" => {
      name: "United States",
      patterns: [ /\bU\.?S\.?A?\b/, "america", "white house", "pentagon", "state department", "american" ],
    },
    "gb" => {
      name: "United Kingdom",
      patterns: [ /\bU\.?K\.?\b/, "britain", "british" ],
    },
    "de" => {
      name: "Germany",
      patterns: [ "german" ],
    },
    "fr" => {
      name: "France",
      patterns: [ "french" ],
    },
    "ae" => {
      name: "United Arab Emirates",
      patterns: [ /\bU\.?A\.?E\.?\b/, "emirati" ],
    },
    "cu" => {
      name: "Cuba",
      patterns: [ "cuban" ],
    },
    "il" => {
      name: "Israel",
      patterns: [ /\bIDF\b/, "israeli", "israeli military", "israeli forces" ],
    },
    "ir" => {
      name: "Iran",
      patterns: [ /\bIRGC\b/, "iranian", "iranian military" ],
    },
    "ru" => {
      name: "Russia",
      patterns: [ "kremlin", "russian", "russian military", "russian forces" ],
    },
    "ua" => {
      name: "Ukraine",
      patterns: [ "ukrainian", "ukrainian military", "ukrainian forces" ],
    },
    "cn" => {
      name: "China",
      patterns: [ "chinese" ],
    },
    "eg" => {
      name: "Egypt",
      patterns: [ "egyptian" ],
    },
    "in" => {
      name: "India",
      patterns: [ "indian" ],
    },
    "iq" => {
      name: "Iraq",
      patterns: [ "iraqi" ],
    },
    "jp" => {
      name: "Japan",
      patterns: [ "japanese" ],
    },
    "kr" => {
      name: "South Korea",
      patterns: [ "south korean", "korean" ],
    },
    "kp" => {
      name: "North Korea",
      patterns: [ "north korean" ],
    },
    "pk" => {
      name: "Pakistan",
      patterns: [ "pakistani" ],
    },
    "sa" => {
      name: "Saudi Arabia",
      patterns: [ "saudi" ],
    },
    "tr" => {
      name: "Turkey",
      patterns: [ "turkish" ],
    },
    "tw" => {
      name: "Taiwan",
      patterns: [ "taiwanese" ],
    },
  }.freeze

  ADDITIONAL_STATE_ACTORS = [
    { canonical_key: "state:om", name: "Oman", actor_type: "state", country_code: "OM", patterns: [ "oman", "omani", "muscat" ] },
    { canonical_key: "state:qa", name: "Qatar", actor_type: "state", country_code: "QA", patterns: [ "qatar", "qatari", "doha" ] },
    { canonical_key: "state:kw", name: "Kuwait", actor_type: "state", country_code: "KW", patterns: [ "kuwait", "kuwaiti" ] },
    { canonical_key: "state:lb", name: "Lebanon", actor_type: "state", country_code: "LB", patterns: [ "lebanon", "lebanese", "beirut" ] },
    { canonical_key: "state:jo", name: "Jordan", actor_type: "state", country_code: "JO", patterns: [ "jordan", "jordanian", "amman" ] },
  ].freeze

  ORGANIZATION_ACTORS = [
    { canonical_key: "org:hamas", name: "Hamas", actor_type: "organization", patterns: [ "hamas" ] },
    { canonical_key: "org:hezbollah", name: "Hezbollah", actor_type: "organization", patterns: [ "hezbollah" ] },
    { canonical_key: "org:houthis", name: "Houthis", actor_type: "organization", patterns: [ "houthi", "houthis" ] },
    { canonical_key: "org:taliban", name: "Taliban", actor_type: "organization", patterns: [ "taliban" ] },
    { canonical_key: "org:nato", name: "NATO", actor_type: "organization", patterns: [ /\bNATO\b/ ] },
    { canonical_key: "org:eu", name: "European Union", actor_type: "organization", patterns: [ "european union", /\bE\.?U\.?\b/ ] },
    { canonical_key: "org:un", name: "United Nations", actor_type: "organization", patterns: [ "united nations", /\bU\.?N\.?\b/ ] },
    { canonical_key: "org:rsf", name: "Rapid Support Forces", actor_type: "organization", patterns: [ /\bRSF\b/, "rapid support forces" ] },
    { canonical_key: "org:saf", name: "Sudanese Armed Forces", actor_type: "organization", patterns: [ /\bSAF\b/, "sudanese armed forces" ] },
    { canonical_key: "org:palestinian-authority", name: "Palestinian Authority", actor_type: "organization", patterns: [ "palestinian authority" ] },
    { canonical_key: "org:isis", name: "Islamic State", actor_type: "organization", patterns: [ /\bISIS\b/, /\bISIL\b/, "islamic state" ] },
  ].freeze

  ACTOR_DEFINITIONS = begin
    state_actors = NewsGeocodable::COUNTRY_NAME_MAP.map do |country_name, code|
      override = STATE_ALIAS_OVERRIDES[code] || {}
      {
        canonical_key: "state:#{code}",
        name: override[:name] || country_name.titleize,
        actor_type: "state",
        country_code: code.upcase,
        patterns: [ country_name, *Array(override[:patterns]) ],
      }
    end

    (state_actors + ADDITIONAL_STATE_ACTORS + ORGANIZATION_ACTORS).uniq { |actor| actor[:canonical_key] }.freeze
  end

  class << self
    def extract(title = nil, summary: nil)
      new.extract(title: title, summary: summary)
    end
  end

  def extract(title:, summary: nil)
    return nil if title.blank?

    full_text = [ title, summary ].compact.join(" ").squish
    actors = extract_actors(full_text)
    return nil if actors.empty?

    rule = EVENT_RULES.find { |event_rule| full_text.match?(event_rule[:regex]) }
    event_family = rule&.fetch(:event_family) || fallback_event_family
    event_type = rule&.fetch(:event_type) || fallback_event_type(actors)
    matched_on = if rule
      title.match?(rule[:regex]) ? "title" : "summary"
    end
    assignments = assign_roles(full_text, actors, rule)
    return nil if assignments.empty?

    {
      event_family: event_family,
      event_type: event_type,
      claim_text: full_text.to_s.scrub("")[0...10_000],
      confidence: claim_confidence(rule, assignments, matched_on),
      extraction_method: "heuristic",
      extraction_version: "headline_summary_rules_v2",
      metadata: {
        "matched_rule" => event_type,
        "matched_on" => matched_on,
        "actor_count" => assignments.size,
        "summary_used" => summary.present?,
      },
      actors: assignments,
    }
  end

  private

  def extract_actors(text)
    lower_text = text.downcase

    ACTOR_DEFINITIONS.filter_map do |actor|
      match = match_actor(actor, text, lower_text)
      next unless match

      actor.merge(match)
    end.sort_by { |actor| [ actor[:position], -actor[:matched_text].length ] }
      .uniq { |actor| actor[:canonical_key] }
  end

  def match_actor(actor, text, lower_text)
    actor[:patterns].filter_map do |pattern|
      if pattern.is_a?(Regexp)
        match = text.match(pattern)
        next unless match

        { position: match.begin(0), matched_text: match[0] }
      else
        match = string_pattern_regex(pattern).match(lower_text)
        next unless match

        { position: match.begin(0), matched_text: text[match.begin(0)...match.end(0)] }
      end
    end.min_by { |match| [ match[:position], match[:matched_text].length ] }
  end

  def assign_roles(text, actors, rule)
    return fallback_roles(actors) unless rule

    case rule[:strategy]
    when :directional
      directional_roles(text, actors, rule[:event_type], initiator_role: "initiator", target_role: "target")
    when :claimant_target
      directional_roles(text, actors, rule[:event_type], initiator_role: "claimant", target_role: "target")
    when :provider_recipient
      directional_roles(text, actors, rule[:event_type], initiator_role: "initiator", target_role: "recipient")
    when :participants
      participant_roles(text, actors)
    when :subject_participants
      actors.size == 1 ? subject_roles(actors) : participant_roles(text, actors)
    when :subject
      subject_roles(actors)
    else
      fallback_roles(actors)
    end
  end

  def directional_roles(text, actors, event_type, initiator_role:, target_role:)
    verb_match = EVENT_RULES.find { |rule| rule[:event_type] == event_type }[:regex].match(text)
    return fallback_roles(actors) unless verb_match

    initiator = actors.select { |actor| actor[:position] < verb_match.begin(0) }.max_by { |actor| actor[:position] } || actors.first
    target = actors.find { |actor| actor[:position] > verb_match.end(0) && actor[:canonical_key] != initiator[:canonical_key] }
    target ||= actors.find { |actor| actor[:canonical_key] != initiator[:canonical_key] }

    assignments = []
    assignments << actor_assignment(initiator, initiator_role, 0.92)
    assignments << actor_assignment(target, target_role, 0.9) if target

    remaining = actors.reject { |actor| [ initiator&.dig(:canonical_key), target&.dig(:canonical_key) ].compact.include?(actor[:canonical_key]) }
    assignments.concat(remaining.map { |actor| actor_assignment(actor, "participant", 0.74) })
    assignments
  end

  def participant_roles(text, actors)
    lower_text = text.downcase

    actors.map do |actor|
      role = if lower_text.include?("mediated by #{actor[:matched_text].downcase}") || lower_text.include?("brokered by #{actor[:matched_text].downcase}")
        "mediator"
      elsif lower_text.include?("hosted by #{actor[:matched_text].downcase}") || actor_host?(lower_text, actor)
        "host"
      else
        "participant"
      end

      confidence = role == "participant" ? 0.84 : 0.78
      actor_assignment(actor, role, confidence)
    end
  end

  def subject_roles(actors)
    return [] if actors.empty?

    assignments = [ actor_assignment(actors.first, "subject", 0.8) ]
    assignments.concat(
      actors.drop(1).map { |actor| actor_assignment(actor, "affected_party", 0.7) }
    )
    assignments
  end

  def fallback_roles(actors)
    return [] if actors.empty?

    if actors.size == 1
      [ actor_assignment(actors.first, "subject", 0.72) ]
    else
      actors.map { |actor| actor_assignment(actor, "participant", 0.68) }
    end
  end

  def actor_host?(lower_text, actor)
    prefix = lower_text[[ actor[:position] - 4, 0 ].max...actor[:position]].to_s
    prefix.match?(/\b(?:in|at)\s+\z/)
  end

  def actor_assignment(actor, role, confidence)
    {
      canonical_key: actor[:canonical_key],
      name: actor[:name],
      actor_type: actor[:actor_type],
      country_code: actor[:country_code],
      role: role,
      matched_text: actor[:matched_text],
      confidence: confidence,
    }
  end

  def fallback_event_family
    "general"
  end

  def fallback_event_type(actors)
    actors.size >= 2 ? "mentioned_relationship" : "actor_mention"
  end

  def claim_confidence(rule, assignments, matched_on)
    return 0.72 if assignments.empty?
    return assignments.first[:confidence] || 0.72 unless rule

    base = case rule[:strategy]
    when :directional, :claimant_target, :provider_recipient
      assignments.size >= 2 ? 0.9 : 0.78
    when :participants
      assignments.size >= 2 ? 0.84 : 0.76
    when :subject
      0.79
    else
      0.72
    end

    base -= 0.04 if matched_on == "summary"

    base.round(2)
  end

  def string_pattern_regex(pattern)
    @string_pattern_regex ||= {}
    @string_pattern_regex[pattern] ||= /(?<![[:alnum:]])#{Regexp.escape(pattern.downcase)}(?![[:alnum:]])/
  end
end
