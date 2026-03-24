class NewsScopeClassifier
  CORE_CATEGORIES = %w[conflict terror disaster cyber unrest health].freeze
  ADJACENT_CATEGORIES = %w[economy diplomacy political science].freeze
  OUT_OF_SCOPE_CATEGORIES = %w[sports entertainment lifestyle food].freeze

  CORE_TERMS = [
    "war", "wars", "strike", "strikes", "airstrike", "airstrikes", "attack", "attacks",
    "bombing", "bomb", "missile", "missiles", "drone", "drones", "invasion", "invaded",
    "troops", "shelling", "artillery", "raid", "raids", "hostage", "hostages", "terror",
    "terrorist", "cyberattack", "cyberattacks", "breach", "breaches", "ransomware",
    "outage", "outages", "blackout", "blackouts", "explosion", "explosions", "coup",
    "rebellion", "insurgency", "earthquake", "earthquakes", "flood", "floods", "wildfire",
    "wildfires", "hurricane", "hurricanes", "typhoon", "typhoons", "epidemic",
    "epidemics", "outbreak", "outbreaks", "famine", "chemical", "nuclear", "military",
    "navy", "army", "insurgent", "insurgents"
  ].freeze

  ADJACENT_TERMS = [
    "talks", "summit", "negotiation", "negotiations", "negotiate", "diplomatic",
    "diplomacy", "ceasefire", "treaty", "sanctions", "tariff", "tariffs", "election",
    "elections", "parliament", "congress", "minister", "ministers", "president",
    "prime minister", "prime-minister", "vote", "votes", "voting", "trade", "oil",
    "gas", "energy", "inflation", "recession", "central bank", "central-bank",
    "shipping", "maritime", "port", "ports", "airline", "airlines", "aviation",
    "telecom", "semiconductor", "semiconductors", "refugee", "refugees", "migration",
    "migrants", "court", "courts", "arrest", "arrests", "trial", "corruption"
  ].freeze

  OUT_OF_SCOPE_TERMS = [
    "recipe", "recipes", "cooking", "cookbook", "baking", "bake", "pasta", "dessert",
    "brunch", "dinner", "lunch", "celebrity", "celebrities", "gossip", "singer",
    "singers", "actor", "actors", "actress", "actresses", "rapper", "rappers", "album",
    "albums", "movie", "movies", "film", "films", "box office", "box-office", "grammy",
    "grammys", "oscar", "oscars", "emmy", "emmys", "red carpet", "red-carpet",
    "reality tv", "fashion", "makeup", "skincare", "beauty", "dating", "boyfriend",
    "girlfriend", "romance", "wedding", "nfl", "nba", "mlb", "nhl", "tennis", "golf",
    "soccer", "football", "cricket", "super bowl", "superbowl", "champions league",
    "premier league", "transfer", "transfer-window", "horoscopes", "horoscope", "travel",
    "tourism", "vacation", "hotel", "hotels"
  ].freeze

  NOISE_TERMS = [
    "casino", "bonus", "sign up", "promo code", "free spins", "jackpot", "sportsbook",
    "odds", "betting", "slot machine", "zodiac"
  ].freeze

  GEOPOLITICAL_TERMS = (
    NewsGeocodable::COUNTRY_NAME_MAP.keys +
    [
      "nato", "hamas", "hezbollah", "houthis", "taliban", "idf", "irgc", "kremlin",
      "white house", "pentagon", "united nations", "european union"
    ]
  ).uniq.freeze

  class << self
    def classify(title:, summary: nil, category: nil)
      text = [ title, summary ].compact.join(" ").downcase
      normalized_category = category.to_s.downcase.presence

      core_hits = matched_terms(text, CORE_TERMS)
      adjacent_hits = matched_terms(text, ADJACENT_TERMS)
      out_of_scope_hits = matched_terms(text, OUT_OF_SCOPE_TERMS)
      noise_hits = matched_terms(text, NOISE_TERMS)
      geopolitical_hits = matched_terms(text, GEOPOLITICAL_TERMS)

      return result("core", "category:#{normalized_category}") if CORE_CATEGORIES.include?(normalized_category)
      return result("adjacent", "category:#{normalized_category}") if ADJACENT_CATEGORIES.include?(normalized_category)
      return result("out_of_scope", "category:#{normalized_category}") if OUT_OF_SCOPE_CATEGORIES.include?(normalized_category)
      return result("out_of_scope", "pattern:location_only") if location_only_title?(title, summary)
      return result("out_of_scope", "keyword:#{noise_hits.first}") if noise_hits.any?

      if out_of_scope_hits.any? && core_hits.empty? && adjacent_hits.empty? && geopolitical_hits.empty?
        return result("out_of_scope", "keyword:#{out_of_scope_hits.first}")
      end

      if core_hits.any?
        return result("core", "keyword:#{core_hits.first}")
      end

      if adjacent_hits.any?
        return result("adjacent", "keyword:#{adjacent_hits.first}")
      end

      if geopolitical_hits.any?
        return result("adjacent", "actor:#{geopolitical_hits.first}")
      end

      result("out_of_scope", "default")
    end

    private

    def matched_terms(text, terms)
      terms.select do |term|
        text.match?(term_regex(term))
      end
    end

    def location_only_title?(title, summary)
      return false if summary.present?

      normalized_title = title.to_s.squish
      return false if normalized_title.blank? || normalized_title.length > 120
      return false unless normalized_title.count(",") >= 2
      return false unless normalized_title.match?(/\A[^,]+(?:,\s*[^,]+){2,3}\z/)

      normalized_title.split(",").all? do |segment|
        segment.squish.split.size <= 4
      end
    end

    def term_regex(term)
      @term_regex ||= {}
      @term_regex[term] ||= /\b#{Regexp.escape(term)}\b/i
    end

    def result(content_scope, scope_reason)
      {
        content_scope: content_scope,
        scope_reason: scope_reason,
      }
    end
  end
end
