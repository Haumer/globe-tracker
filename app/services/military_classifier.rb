class MilitaryClassifier
  # Known military callsign prefixes by region
  # NOTE: Avoid airline ICAO codes here (e.g. UAE=Emirates, SAA=SAA, THY=Turkish)
  CALLSIGN_PREFIXES = %w[
    RCH RRR DUKE EVAC KING FORTE JAKE HOMER IRON DOOM VIPER RAGE REAPER
    TOPCAT NAVY ARMY CNV PAT SPAR SAM EXEC
    NATO MMF GAF BAF RFR IAM ASCOT RRF CFC SHF PLF HAF HRZ TUAF FAB RFAF
    IAF ISF IQF JOF KEF KAF KUF LBF OMF PAF QAF RSF YAF
    CABAL CHAOS COBRA COMET DEMON DINGO DRAAK GHOST HAWK HYDRA
    JESTER KNIFE LANCE MAGIC NIGHT RADON ROGUE SKULL SNAKE STORM
    SWORD TALON TIGER TONIC TOXIC TRIDENT VENOM WOLF
  ].freeze

  # ICAO hex ranges allocated specifically to military by country
  # Only includes known dedicated military sub-blocks, NOT entire country allocations.
  # Countries without dedicated mil hex blocks rely on callsign detection only.
  HEX_RANGES = [
    # United States (dedicated military block)
    ["ae0000", "afffff", "US"],
    ["adf7c8", "afffff", "US"],
    # United Kingdom (military sub-block)
    ["43c000", "43cfff", "UK"],
    # France (military sub-block)
    ["3a8000", "3affff", "FR"],
    # Germany (military sub-block)
    ["3f4000", "3f7fff", "DE"],
    # Italy (military sub-block)
    ["33ff00", "33ffff", "IT"],
    # Netherlands
    ["472000", "473fff", "NL"],
    # Norway
    ["480000", "480fff", "NO"],
    # Spain
    ["340000", "340fff", "ES"],
    # Belgium (military sub-block only — 448000-44807f; 449000+ is civil)
    ["448000", "44807f", "BE"],
    # Turkey (narrowed — 4b8000-4b8fff is too broad, catches Pegasus/Turkish Airlines)
    # Turkish military typically uses 4b8000-4b80ff
    ["4b8000", "4b80ff", "TR"],
    # Greece
    ["468000", "468fff", "GR"],
    # Poland
    ["48d800", "48d87f", "PL"],
    # Canada (military sub-block)
    ["c0cdf9", "c3ffff", "CA"],
    # Australia (military sub-block)
    ["7cf800", "7cfaff", "AU"],
    # Sweden
    ["4a0000", "4a0fff", "SE"],
    # Denmark
    ["458000", "458fff", "DK"],
    # Finland
    ["460000", "460fff", "FI"],
    # Czech Republic
    ["498000", "498fff", "CZ"],
    # Romania
    ["4a4000", "4a4fff", "RO"],
  ].freeze

  # Additional callsign patterns (regex-based) for Middle East / non-NATO
  CALLSIGN_PATTERNS = [
    /^IF[A-Z]\d/i,     # Israeli Air Force
    /^RSAF\d/i,        # Royal Saudi Air Force
    /^UAEAF/i,         # UAE Air Force
    /^QAF\d/i,         # Qatar Air Force
    /^RJAF/i,          # Royal Jordanian Air Force
    /^EAF\d/i,         # Egyptian Air Force
    /^PAF\d/i,         # Pakistani Air Force
    /^AERO\d/i,        # Generic military aero
    /^TAF\d/i,         # Turkish Air Force
  ].freeze

  # Known airline ICAO prefixes that should NEVER be classified as military.
  # Prevents false positives when hex ranges overlap civil/military allocations.
  CIVILIAN_PREFIXES = %w[
    PGT THY SXS ANA TKJ OHY KKK SHT XAK TAK
    UAE ETD QTR SIA MAS CPA CES CSN CCA AIR
    BAW DLH AFR KLM SAS AUA BEL FIN LOT CSA
    TAP IBE SWR AZA
  ].freeze

  def self.military?(icao24:, callsign: nil)
    return false if civilian_callsign?(callsign)
    return true if military_callsign?(callsign)
    return true if military_hex?(icao24)
    false
  end

  def self.civilian_callsign?(callsign)
    return false if callsign.blank?
    cs = callsign.strip.upcase
    CIVILIAN_PREFIXES.any? { |p| cs.start_with?(p) }
  end

  def self.military_callsign?(callsign)
    return false if callsign.blank?
    cs = callsign.strip.upcase

    CALLSIGN_PREFIXES.any? { |p| cs.start_with?(p) } ||
      CALLSIGN_PATTERNS.any? { |pat| cs.match?(pat) }
  end

  def self.military_hex?(hex)
    return false if hex.blank?
    h = hex.strip.downcase

    HEX_RANGES.any? { |start_hex, end_hex, _country| h >= start_hex && h <= end_hex }
  end

  def self.country_for_hex(hex)
    return nil if hex.blank?
    h = hex.strip.downcase

    match = HEX_RANGES.find { |start_hex, end_hex, _| h >= start_hex && h <= end_hex }
    match&.last
  end
end
