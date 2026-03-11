class SatelliteClassifier
  # Military satellite classification by name pattern
  # Maps name patterns to [operator, mission_type]
  MILITARY_PATTERNS = {
    # US - National Reconnaissance Office (NRO) / imagery
    /PRAETORIAN|SDA[_\s]/i => ["US SDA", "milcomms"],
    /NROL/i => ["US NRO", "reconnaissance"],
    /KH-?\d/i => ["US NRO", "imaging"],
    /LACROSSE/i => ["US NRO", "radar_imaging"],
    /ONYX/i => ["US NRO", "radar_imaging"],
    /TOPAZ/i => ["US NRO", "radar_imaging"],
    /MISTY/i => ["US NRO", "stealth_recon"],
    /MENTOR/i => ["US NRO", "sigint"],
    /ORION/i => ["US NRO", "sigint"],
    /TRUMPET/i => ["US NRO", "sigint"],
    /INTRUDER/i => ["US NRO", "sigint"],
    /MERCURY/i => ["US NRO", "sigint"],

    # US - DoD Communications
    /WGS/i => ["US DoD", "milcomms"],
    /AEHF/i => ["US DoD", "milcomms"],
    /MILSTAR/i => ["US DoD", "milcomms"],
    /MUOS/i => ["US DoD", "milcomms"],
    /UFO\s*\d/i => ["US DoD", "milcomms"],
    /FLTSATCOM/i => ["US DoD", "milcomms"],
    /DSCS/i => ["US DoD", "milcomms"],
    /SDS/i => ["US DoD", "relay"],

    # US - Early Warning / Missile Defense
    /SBIRS/i => ["US DoD", "early_warning"],
    /DSP/i => ["US DoD", "early_warning"],
    /STSS/i => ["US MDA", "missile_defense"],

    # US - Space Surveillance / Awareness
    /GSSAP/i => ["US SpaceForce", "space_surveillance"],
    /SAPPHIRE/i => ["Canada DND", "space_surveillance"],

    # US - Navigation (military GPS)
    /NAVSTAR/i => ["US SpaceForce", "navigation"],
    /GPS\s*(II|III)/i => ["US SpaceForce", "navigation"],

    # US - Weather (military)
    /DMSP/i => ["US DoD", "weather"],

    # Russia
    /COSMOS/i => ["Russia MoD", nil], # Generic
    /KOSMOS/i => ["Russia MoD", nil],
    /LUCH/i => ["Russia MoD", "relay"],
    /KONDOR/i => ["Russia MoD", "radar_imaging"],
    /BARS/i => ["Russia MoD", "radar_imaging"],
    /PERSONA/i => ["Russia MoD", "imaging"],
    /GLONASS/i => ["Russia", "navigation"],
    /LOTOS/i => ["Russia MoD", "sigint"],
    /PION/i => ["Russia MoD", "sigint"],
    /TUNDRA/i => ["Russia MoD", "early_warning"],
    /EKS/i => ["Russia MoD", "early_warning"],

    # China
    /YAOGAN/i => ["China PLA", "reconnaissance"],
    /SHIJIAN/i => ["China PLA", "experimental"],
    /GAOFEN/i => ["China", "imaging"],
    /BEIDOU/i => ["China", "navigation"],
    /TIANLIAN/i => ["China", "relay"],

    # UK
    /SKYNET/i => ["UK MoD", "milcomms"],

    # France
    /HELIOS/i => ["France DGA", "imaging"],
    /PLEIADES.*NEO/i => ["France DGA", "imaging"],
    /CSO/i => ["France DGA", "imaging"],
    /SYRACUSE/i => ["France DGA", "milcomms"],
    /CERES/i => ["France DGA", "sigint"],

    # Germany
    /SARAH/i => ["Germany BAAINBw", "radar_imaging"],
    /SAR-LUPE/i => ["Germany BAAINBw", "radar_imaging"],

    # Italy
    /COSMO-SKYMED/i => ["Italy ASI", "radar_imaging"],
    /SICRAL/i => ["Italy MoD", "milcomms"],

    # Japan
    /IGS/i => ["Japan Cabinet", "imaging"],

    # Israel
    /OFEQ/i => ["Israel MoD", "imaging"],
    /EROS/i => ["Israel IAI", "imaging"],
    /TECSAR/i => ["Israel MoD", "radar_imaging"],

    # India
    /RISAT/i => ["India ISRO", "radar_imaging"],
    /CARTOSAT/i => ["India ISRO", "imaging"],
    /EMISAT/i => ["India DRDO", "sigint"],
    /GSAT.*7/i => ["India MoD", "milcomms"],

    # South Korea
    /KOMPSAT/i => ["South Korea", "imaging"],

    # NATO
    /NATO/i => ["NATO", "milcomms"],

    # Turkey
    /GOKTURK/i => ["Turkey MoD", "imaging"],

    # UAE
    /FALCON\s*EYE/i => ["UAE", "imaging"],

    # Saudi Arabia
    /SAUDISAT/i => ["Saudi Arabia", "imaging"],

    # Pakistan
    /PAKTES/i => ["Pakistan", "experimental"],

    # Iran
    /NOOR/i => ["Iran IRGC", "reconnaissance"],
    /KHAYYAM/i => ["Iran", "imaging"],
  }.freeze

  MISSION_TYPE_LABELS = {
    "reconnaissance" => "Reconnaissance",
    "imaging" => "Optical Imaging",
    "radar_imaging" => "Radar Imaging (SAR)",
    "sigint" => "Signals Intelligence",
    "milcomms" => "Military Communications",
    "early_warning" => "Early Warning / Missile Defense",
    "missile_defense" => "Missile Defense",
    "navigation" => "Navigation",
    "weather" => "Military Weather",
    "relay" => "Data Relay",
    "space_surveillance" => "Space Surveillance",
    "experimental" => "Experimental / Technology",
    "stealth_recon" => "Stealth Reconnaissance",
  }.freeze

  def self.classify(name)
    return { operator: nil, mission_type: nil } if name.blank?

    MILITARY_PATTERNS.each do |pattern, (operator, mission_type)|
      if name.match?(pattern)
        return { operator: operator, mission_type: mission_type }
      end
    end

    { operator: nil, mission_type: nil }
  end

  def self.enrich_all!
    count = 0
    # Classify military category and any satellite matching military patterns (e.g. GEO mil sats)
    Satellite.find_each do |sat|
      result = classify(sat.name)
      next if result[:operator].nil? && result[:mission_type].nil?
      next if sat.operator == result[:operator] && sat.mission_type == result[:mission_type]

      sat.update_columns(operator: result[:operator], mission_type: result[:mission_type])
      count += 1
    end
    count
  end
end
