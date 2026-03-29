class CrossLayerAnalyzer
  module Definitions
    INSIGHT_RULE_METHODS = %i[
      earthquake_infrastructure_threats
      jamming_flight_impacts
      conflict_military_surge
      fire_pipeline_threats
      cable_outage_correlations
      emergency_squawk_correlations
      ship_cable_proximity
      outage_conflict_blackout
      notam_military_correlations
      earthquake_pipeline_threats
      weather_flight_disruption
      conflict_pulse_hotspots
      chokepoint_disruptions
      chokepoint_market_stress
      outage_currency_stress
    ].freeze

    COUNTRY_CURRENCY_MAP = {
      "AU" => "AUD",
      "AT" => "EUR",
      "BE" => "EUR",
      "BR" => "BRL",
      "CA" => "CAD",
      "CH" => "CHF",
      "CN" => "CNY",
      "DE" => "EUR",
      "ES" => "EUR",
      "FI" => "EUR",
      "FR" => "EUR",
      "GB" => "GBP",
      "GR" => "EUR",
      "IE" => "EUR",
      "IN" => "INR",
      "IT" => "EUR",
      "JP" => "JPY",
      "NL" => "EUR",
      "PT" => "EUR",
      "RU" => "RUB",
    }.freeze

    COUNTRY_CENTROIDS = {
      "AD" => [42.5, 1.5], "AE" => [24, 54], "AF" => [33, 65], "AL" => [41, 20], "AM" => [40, 45],
      "AO" => [-12.5, 18.5], "AR" => [-34, -64], "AT" => [47.5, 13.5], "AU" => [-25, 135],
      "AZ" => [40.5, 47.5], "BA" => [44, 18], "BD" => [24, 90], "BE" => [50.8, 4], "BG" => [43, 25],
      "BH" => [26, 50.6], "BR" => [-10, -55], "BY" => [53, 28], "CA" => [60, -95], "CD" => [-2.5, 23.5],
      "CH" => [47, 8], "CL" => [-30, -71], "CM" => [6, 12], "CN" => [35, 105], "CO" => [4, -72],
      "CU" => [22, -80], "CY" => [35, 33], "CZ" => [49.75, 15.5], "DE" => [51, 9], "DK" => [56, 10],
      "DZ" => [28, 3], "EC" => [-2, -77.5], "EE" => [59, 26], "EG" => [27, 30], "ES" => [40, -4],
      "ET" => [8, 38], "FI" => [64, 26], "FR" => [46, 2], "GB" => [54, -2], "GE" => [42, 43.5],
      "GH" => [8, -1.2], "GR" => [39, 22], "HR" => [45.2, 15.5], "HU" => [47, 20], "ID" => [-5, 120],
      "IE" => [53, -8], "IL" => [31.5, 34.8], "IN" => [20, 77], "IQ" => [33, 44], "IR" => [32, 53],
      "IS" => [65, -18], "IT" => [42.8, 12.8], "JM" => [18.1, -77.3], "JO" => [31, 36], "JP" => [36, 138],
      "KE" => [1, 38], "KR" => [37, 128], "KW" => [29.5, 47.8], "KZ" => [48, 68], "LB" => [33.8, 35.8],
      "LK" => [7, 81], "LT" => [56, 24], "LV" => [57, 25], "LY" => [25, 17], "MA" => [32, -5],
      "MM" => [22, 98], "MX" => [23, -102], "MY" => [2.5, 112.5], "MZ" => [-18.3, 35], "NG" => [10, 8],
      "NL" => [52.5, 5.8], "NO" => [62, 10], "NZ" => [-42, 174], "OM" => [21, 57], "PA" => [9, -80],
      "PE" => [-10, -76], "PH" => [13, 122], "PK" => [30, 70], "PL" => [52, 20], "PT" => [39.5, -8],
      "QA" => [25.5, 51.3], "RO" => [46, 25], "RS" => [44, 21], "RU" => [60, 100], "SA" => [25, 45],
      "SD" => [16, 30], "SE" => [62, 15], "SG" => [1.4, 103.8], "SI" => [46.1, 14.8], "SK" => [48.7, 19.5],
      "SY" => [35, 38], "TH" => [15, 100], "TN" => [34, 9], "TR" => [39, 35], "TW" => [23.5, 121],
      "TZ" => [-6, 35], "UA" => [49, 32], "UG" => [1, 32], "US" => [38, -97], "UY" => [-33, -56],
      "VE" => [8, -66], "VN" => [16, 108], "YE" => [15, 48], "ZA" => [-29, 24], "ZM" => [-15, 30],
      "ZW" => [-20, 30],
    }.freeze
  end
end
