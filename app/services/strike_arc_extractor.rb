class StrikeArcExtractor
  # Actors/locations with canonical coordinates (capital or military center)
  ACTORS = {
    "israel" => { name: "Israel", lat: 31.8, lng: 35.2 },
    "iran" => { name: "Iran", lat: 35.7, lng: 51.4 },
    "russia" => { name: "Russia", lat: 55.8, lng: 37.6 },
    "ukraine" => { name: "Ukraine", lat: 50.4, lng: 30.5 },
    "lebanon" => { name: "Lebanon", lat: 33.9, lng: 35.5 },
    "iraq" => { name: "Iraq", lat: 33.3, lng: 44.4 },
    "syria" => { name: "Syria", lat: 33.5, lng: 36.3 },
    "gaza" => { name: "Gaza", lat: 31.5, lng: 34.5 },
    "yemen" => { name: "Yemen", lat: 15.4, lng: 44.2 },
    "pakistan" => { name: "Pakistan", lat: 33.7, lng: 73.0 },
    "afghanistan" => { name: "Afghanistan", lat: 34.5, lng: 69.2 },
    "kuwait" => { name: "Kuwait", lat: 29.4, lng: 48.0 },
    "saudi arabia" => { name: "Saudi Arabia", lat: 24.7, lng: 46.7 },
    "dubai" => { name: "Dubai", lat: 25.2, lng: 55.3 },
    "cuba" => { name: "Cuba", lat: 23.1, lng: -82.4 },
    "sudan" => { name: "Sudan", lat: 15.6, lng: 32.5 },
    "myanmar" => { name: "Myanmar", lat: 19.8, lng: 96.1 },
    "somalia" => { name: "Somalia", lat: 2.0, lng: 45.3 },
    "libya" => { name: "Libya", lat: 32.9, lng: 13.2 },
    "north korea" => { name: "North Korea", lat: 39.0, lng: 125.8 },
    # Specific cities/targets
    "tehran" => { name: "Tehran", lat: 35.7, lng: 51.4 },
    "isfahan" => { name: "Isfahan", lat: 32.7, lng: 51.7 },
    "tel aviv" => { name: "Tel Aviv", lat: 32.1, lng: 34.8 },
    "baghdad" => { name: "Baghdad", lat: 33.3, lng: 44.4 },
    "beirut" => { name: "Beirut", lat: 33.9, lng: 35.5 },
    "kyiv" => { name: "Kyiv", lat: 50.4, lng: 30.5 },
    "kharkiv" => { name: "Kharkiv", lat: 50.0, lng: 36.2 },
    "moscow" => { name: "Moscow", lat: 55.8, lng: 37.6 },
    "riyadh" => { name: "Riyadh", lat: 24.7, lng: 46.7 },
    "hormuz" => { name: "Strait of Hormuz", lat: 26.6, lng: 56.3 },
    "donbas" => { name: "Donbas", lat: 48.0, lng: 37.8 },
    "odesa" => { name: "Odesa", lat: 46.5, lng: 30.7 },
    "crimea" => { name: "Crimea", lat: 44.9, lng: 34.1 },
    "kandahar" => { name: "Kandahar", lat: 31.6, lng: 65.7 },
    # Groups (mapped to their primary base)
    "hezbollah" => { name: "Hezbollah", lat: 33.9, lng: 35.5 },
    "houthi" => { name: "Houthis", lat: 15.4, lng: 44.2 },
    "hamas" => { name: "Hamas", lat: 31.5, lng: 34.5 },
    "taliban" => { name: "Taliban", lat: 34.5, lng: 69.2 },
  }.freeze

  # Sorted longest-first to match "saudi arabia" before "saudi"
  ACTOR_KEYS = ACTORS.keys.sort_by { |k| -k.length }.freeze

  # Action verbs that indicate directionality
  ATTACK_VERBS = /\b(strikes?|attacks?|bombs?|hits?|shells?|targets?|invades?|fires?\s+(?:at|on|into)|launches?\s+(?:at|on|against|into)|missiles?\s+(?:hit|strike|on)|drones?\s+(?:hit|strike|attack|on))\b/i

  MAX_ARCS = 30

  def self.extract(headlines)
    new.extract(headlines)
  end

  def extract(headlines)
    pairs = Hash.new { |h, k| h[k] = { count: 0, samples: [] } }

    headlines.each do |title|
      next if title.blank?
      lower = title.downcase

      # Find all actors/locations mentioned
      mentioned = ACTOR_KEYS.select { |k| lower.include?(k) }
      next if mentioned.size < 2

      # Try directional: "{ACTOR} {verb} {TARGET}"
      mentioned.each do |actor_key|
        actor_pos = lower.index(actor_key)
        next unless actor_pos
        after_actor = lower[actor_pos + actor_key.length..]

        next unless after_actor&.match?(ATTACK_VERBS)
        verb_match = after_actor.match(ATTACK_VERBS)
        after_verb = after_actor[verb_match.end(0)..]

        mentioned.each do |target_key|
          next if target_key == actor_key
          # Skip if same coordinates (e.g., iran/tehran, ukraine/kyiv)
          next if ACTORS[actor_key][:lat] == ACTORS[target_key][:lat] &&
                  ACTORS[actor_key][:lng] == ACTORS[target_key][:lng]

          if after_verb&.include?(target_key)
            key = "#{ACTORS[actor_key][:name]}→#{ACTORS[target_key][:name]}"
            pairs[key][:count] += 1
            pairs[key][:samples] << title.truncate(100) if pairs[key][:samples].size < 3
            pairs[key][:from] = ACTORS[actor_key]
            pairs[key][:to] = ACTORS[target_key]
          end
        end
      end
    end

    # Return top arcs sorted by count
    pairs.sort_by { |_, v| -v[:count] }
      .first(MAX_ARCS)
      .map do |key, data|
        {
          from_name: data[:from][:name],
          from_lat: data[:from][:lat],
          from_lng: data[:from][:lng],
          to_name: data[:to][:name],
          to_lat: data[:to][:lat],
          to_lng: data[:to][:lng],
          count: data[:count],
          sample_headlines: data[:samples],
        }
      end
  end
end
