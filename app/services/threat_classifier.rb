class ThreatClassifier
  CRITICAL_TARGETS = %w[iran russia china taiwan nato nuclear].freeze
  MILITARY_ESCALATION = %w[attack strike bomb missile launch invasion troops deployed airstrike].freeze
  CONFLICT_WORDS = %w[war battle fighting conflict killed soldiers casualties combat artillery shelling drone].freeze
  TERROR_WORDS = %w[terrorism terrorist bombing hostage hijack explosion].freeze
  PROTEST_WORDS = %w[protest rally demonstration riot uprising coup revolution rebellion].freeze
  DISASTER_WORDS = %w[earthquake tsunami hurricane tornado wildfire volcano flood cyclone landslide avalanche].freeze
  HEALTH_WORDS = %w[pandemic outbreak epidemic virus infection disease vaccine].freeze
  ECONOMY_WORDS = %w[recession inflation crash bankruptcy sanctions tariff default].freeze
  DIPLOMACY_WORDS = %w[peace ceasefire treaty summit negotiate agreement diplomatic].freeze
  CYBER_WORDS = %w[cyberattack hack breach ransomware malware ddos].freeze

  SOFTENER_WORDS = %w[
    peace proposal talks agreement summit ceasefire deal treaty negotiate
    negotiation diplomatic diplomacy resolution accord reconciliation
    cooperation aid humanitarian relief support
  ].freeze

  HISTORICAL_PATTERNS = [
    /\bin \d{4}\b/,           # "in 2003"
    /\bduring ww/i,           # "during WWII", "during WWI"
    /\bhistorical(ly)?\b/i,
    /\banniversary of\b/i,
    /\byears ago\b/i,
    /\bcommemorat/i,          # "commemorate", "commemoration"
    /\bformer\b/i,
    /\bonce was\b/i,
  ].freeze

  QUESTION_PREFIXES = /\A(could|should|will|is|are|what if|does|do|has|have|can|would|might)\b/i
  OPINION_MARKERS = /\b(opinion:|editorial:|analysis:|commentary:|op-ed:|perspective:)\b/i

  POSITIVE_OUTCOME_WORDS = %w[
    rescued saved survived recovered ceasefire\ agreed deal\ reached
    peace restored liberated reunited stabilized resolved
  ].freeze

  # Category definitions with base scores
  # Severity order (for tie-breaking): conflict > terror > disaster > cyber > unrest > health > economy > diplomacy
  CATEGORIES = [
    { name: "conflict",  words: MILITARY_ESCALATION + CONFLICT_WORDS, base_threat: "high",     base_tone: -4.0, severity_rank: 0 },
    { name: "terror",    words: TERROR_WORDS,                         base_threat: "critical", base_tone: -7.0, severity_rank: 1 },
    { name: "disaster",  words: DISASTER_WORDS,                       base_threat: "high",     base_tone: -3.0, severity_rank: 2 },
    { name: "cyber",     words: CYBER_WORDS,                          base_threat: "high",     base_tone: -4.0, severity_rank: 3 },
    { name: "unrest",    words: PROTEST_WORDS,                        base_threat: "medium",   base_tone: -2.0, severity_rank: 4 },
    { name: "health",    words: HEALTH_WORDS,                         base_threat: "medium",   base_tone: -2.0, severity_rank: 5 },
    { name: "economy",   words: ECONOMY_WORDS,                       base_threat: "medium",   base_tone: -2.0, severity_rank: 6 },
    { name: "diplomacy", words: DIPLOMACY_WORDS,                     base_threat: "low",      base_tone:  1.0, severity_rank: 7 },
  ].freeze

  THREAT_LEVELS = %w[info low medium high critical].freeze

  class << self
    # Classify a headline -> { category:, threat:, tone:, level:, keywords: }
    def classify(title)
      lower = title.to_s.downcase

      has_softener = SOFTENER_WORDS.any? { |w| lower.match?(/\b#{Regexp.escape(w)}\b/) }
      has_historical = HISTORICAL_PATTERNS.any? { |p| lower.match?(p) }
      has_question = lower.match?(QUESTION_PREFIXES) || lower.match?(OPINION_MARKERS)
      has_positive = POSITIVE_OUTCOME_WORDS.any? { |w| lower.match?(/\b#{Regexp.escape(w)}\b/) }
      has_critical_target = CRITICAL_TARGETS.any? { |t| lower.match?(/\b#{Regexp.escape(t)}\b/) }
      has_military_escalation = MILITARY_ESCALATION.any? { |w| lower.match?(/\b#{Regexp.escape(w)}\b/) }

      # Score every category — use word-boundary matching to avoid false positives
      # (e.g., "warmer" matching "war", "attacking" matching "attack")
      scored = CATEGORIES.map do |cat|
        matched = cat[:words].select { |w| lower.match?(/\b#{Regexp.escape(w)}\b/) }
        next nil if matched.empty?

        score = matched.size # +1 per keyword match

        # Critical target escalation for conflict
        if cat[:name] == "conflict" && has_critical_target
          score += 2
        end

        # Context-aware deductions
        score -= 2 if has_softener
        score -= 3 if has_historical

        { cat: cat, score: score, matched: matched }
      end.compact

      return default_result if scored.empty?

      # Pick highest score; break ties by severity rank (lower rank = higher severity)
      best = scored.max_by { |s| [ s[:score], -s[:cat][:severity_rank] ] }

      cat = best[:cat]
      matched = best[:matched]
      threat = cat[:base_threat]
      tone = cat[:base_tone]

      # Critical-target military escalation for conflict
      if cat[:name] == "conflict" && has_critical_target && has_military_escalation && !has_softener && !has_historical
        threat = "critical"
        tone = -8.0
      end

      # Historical reference: downgrade to info
      if has_historical
        threat = "info"
        tone = [ tone + 3.0, 0.0 ].min
      end

      # Question/opinion: downgrade one level
      if has_question
        threat = downgrade_threat(threat)
        tone = [ tone + 1.5, 0.0 ].min
      end

      # Softener near conflict/terror: downgrade severity
      if has_softener && %w[conflict terror].include?(cat[:name])
        threat = downgrade_threat(threat)
        tone = [ tone + 2.0, 0.0 ].min
      end

      # Positive outcome: shift tone upward
      if has_positive
        tone = [ tone + 2.0, 1.0 ].min
        threat = downgrade_threat(threat) if tone > -2.0
      end

      { category: cat[:name], threat: threat, tone: tone.round(1),
        level: tone_level(tone), keywords: matched }
    end

    def tone_level(tone)
      if tone <= -5 then "critical"
      elsif tone <= -2 then "negative"
      elsif tone <= 2 then "neutral"
      else "positive"
      end
    end

    # Categorize from GDELT theme strings
    def categorize_themes(themes)
      return "conflict" if themes.any? { |t| t.include?("ARMEDCONFLICT") || t.include?("MILITARY") || t.include?("TERROR") }
      return "unrest"   if themes.any? { |t| t.include?("PROTEST") || t.include?("REBELLION") || t.include?("COUP") }
      return "disaster" if themes.any? { |t| t.include?("ENV_") || t.include?("EARTHQUAKE") || t.include?("VOLCANO") || t.include?("FLOOD") || t.include?("WILDFIRE") || t.include?("HURRICANE") }
      return "health"   if themes.any? { |t| t.include?("HEALTH") || t.include?("PANDEMIC") || t.include?("EPIDEMIC") || t.include?("MEDICAL") }
      return "economy"  if themes.any? { |t| t.include?("ECON_") || t.include?("POVERTY") || t.include?("FAMINE") }
      return "diplomacy" if themes.any? { |t| t.include?("PEACE") || t.include?("CEASEFIRE") }
      "other"
    end

    private

    def default_result
      { category: "other", threat: "info", tone: 0.0, level: "neutral", keywords: [] }
    end

    def downgrade_threat(threat)
      idx = THREAT_LEVELS.index(threat) || 0
      THREAT_LEVELS[[ idx - 1, 0 ].max]
    end
  end
end
