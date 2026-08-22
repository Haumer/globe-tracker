# The numbers a headline asserts: "at least 69 killed", "death toll rises to
# 111", "kills 12, injures 30". Deliberately numeric-only -- "dozens feared
# dead" is a real claim but not a plottable one, and guessing a number for it
# would put an invented point on a chart of reported figures.
#
# One figure per kind, keeping the largest: a headline saying "12 killed" and
# "death toll hits 12" is one assertion, not two, and when a single headline
# carries both an early figure and a revision the revision is the claim.
class CasualtyFigureParser
  QUALIFIER = /(?:at\s+least|more\s+than|over|up\s+to|about|around|nearly|some)/i
  NUMBER = /\d{1,3}(?:,\d{3})+|\d+/

  # "up to" bounds from above and "at least" from below; both get kept and
  # labelled rather than collapsed, so the chart can hedge the point.
  AT_LEAST = /\A(?:at\s+least|more\s+than|over)\z/i

  PATTERNS = {
    "killed" => [
      # Revisions phrase freely -- "death toll later rises to", "toll now at" --
      # so this takes the first number within reach of the phrase instead of
      # enumerating verbs.
      /death\s+toll[^0-9]{0,30}?(#{QUALIFIER}\s+)?(#{NUMBER})/i,
      /\bkill(?:s|ed|ing)\s+(#{QUALIFIER}\s+)?(#{NUMBER})\b/i,
      /(#{QUALIFIER}\s+)?(#{NUMBER})\s+(?:people|civilians|migrants|soldiers|troops|workers|miners|passengers|villagers|children|pilgrims|others)?\s*(?:are\s+|were\s+|reported\s+|feared\s+|confirmed\s+)?(?:killed|dead|died|dies?\b|deaths)/i,
      /\bleaves?\s+(#{QUALIFIER}\s+)?(#{NUMBER})\s+dead/i,
    ],
    "injured" => [
      /\b(?:injur(?:es|ed|ing)|wound(?:s|ed|ing))\s+(#{QUALIFIER}\s+)?(#{NUMBER})\b/i,
      /(#{QUALIFIER}\s+)?(#{NUMBER})\s+(?:people\s+|others\s+)?(?:injured|wounded|hurt\b)/i,
    ],
    "missing" => [
      /(#{QUALIFIER}\s+)?(#{NUMBER})\s+(?:people\s+|others\s+)?(?:missing|unaccounted)/i,
      /\bmissing\s*[:—-]\s*(#{QUALIFIER}\s+)?(#{NUMBER})\b/i,
    ],
  }.freeze

  def self.parse(text)
    return [] if text.blank?

    PATTERNS.filter_map do |kind, patterns|
      hits = patterns.flat_map do |pattern|
        text.to_s.scan(pattern).map do |qualifier, number|
          { value: number.delete(",").to_i, qualifier: normalize_qualifier(qualifier) }
        end
      end.select { |hit| hit[:value].positive? }
      next if hits.empty?

      best = hits.max_by { |hit| hit[:value] }
      { "kind" => kind, "value" => best[:value], "qualifier" => best[:qualifier] }.compact
    end
  end

  def self.normalize_qualifier(matched)
    return nil if matched.blank?

    AT_LEAST.match?(matched.squish) ? "at_least" : "about"
  end
end
