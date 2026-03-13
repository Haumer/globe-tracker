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

  # Category → { words:, threat:, tone: }
  CATEGORIES = [
    { name: "conflict",  words: MILITARY_ESCALATION + CONFLICT_WORDS, threat: "high",     tone: -4.0 },
    { name: "conflict",  words: TERROR_WORDS,                         threat: "critical",  tone: -7.0 },
    { name: "disaster",  words: DISASTER_WORDS,                       threat: "high",      tone: -3.0 },
    { name: "unrest",    words: PROTEST_WORDS,                        threat: "medium",    tone: -2.0 },
    { name: "cyber",     words: CYBER_WORDS,                          threat: "high",      tone: -4.0 },
    { name: "health",    words: HEALTH_WORDS,                         threat: "medium",    tone: -2.0 },
    { name: "economy",   words: ECONOMY_WORDS,                        threat: "medium",    tone: -2.0 },
    { name: "diplomacy", words: DIPLOMACY_WORDS,                      threat: "low",       tone:  1.0 },
  ].freeze

  class << self
    # Classify a headline → { category:, threat:, tone:, level:, keywords: }
    def classify(title)
      lower = title.to_s.downcase

      CATEGORIES.each do |cat|
        matched = cat[:words].select { |w| lower.include?(w) }
        next if matched.empty?

        threat = cat[:threat]
        tone = cat[:tone]

        # Escalate conflict → critical when critical targets + military action
        if cat[:name] == "conflict" && cat[:threat] == "high" &&
           CRITICAL_TARGETS.any? { |t| lower.include?(t) } &&
           MILITARY_ESCALATION.any? { |w| lower.include?(w) }
          threat = "critical"
          tone = -8.0
        end

        return { category: cat[:name], threat: threat, tone: tone.round(1),
                 level: tone_level(tone), keywords: matched }
      end

      { category: "other", threat: "info", tone: 0.0, level: "neutral", keywords: [] }
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
  end
end
