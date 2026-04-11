class OntologyRelationshipSyncService
  module Definitions
    DEFAULT_CLUSTER_WINDOW = 72.hours
    DIRECT_STORY_WINDOW = 7.days
    RELATION_DERIVED_BY = "ontology_relationship_sync_v1".freeze
    CHOKEPOINT_ENTITY_TYPE = "corridor".freeze
    THEATER_ENTITY_TYPE = "theater".freeze
    COMMODITY_ENTITY_TYPE = "commodity".freeze
    ASSET_ENTITY_TYPES = {
      airport: "airport",
      military_base: "military_base",
      port: "port",
      power_plant: "power_plant",
      submarine_cable: "submarine_cable",
    }.freeze
    CORROBORATED_NEWS_STATUSES = %w[multi_source cross_layer_corroborated].freeze
    THEATER_PRESSURE_TARGETS = {
      "Middle East / Iran War" => %i[hormuz bab_el_mandeb suez],
      "Russia-Ukraine War" => %i[bosphorus danish_straits],
    }.freeze
    COMMODITY_FLOW_TYPES = {
      "OIL_WTI" => :oil,
      "OIL_BRENT" => :oil,
      "LNG" => :lng,
      "GAS_NAT" => :lng,
      "WHEAT" => :grain,
      "COPPER" => :trade,
      "IRON" => :trade,
    }.freeze
    DIRECT_STORY_TERMS = %w[
      shipping ship ships tanker tankers maritime vessel vessels navigation transit
      blockade blocked blocking reopen reopened closure closed lane lanes
      freight cargo oil lng gas energy port ports
    ].freeze
    DOWNSTREAM_ASSET_LIMITS = {
      airport: 4,
      military_base: 4,
      power_plant: 4,
      submarine_cable: 4,
    }.freeze
    OPERATIONAL_ACTIVITY_LIMITS = {
      chokepoint_ship: 6,
      cable_ship: 4,
      theater_flight: 6,
      strategic_air_asset_flight: 3,
    }.freeze
    INFRASTRUCTURE_DISRUPTION_EVENT_WINDOW = 72.hours
    INFRASTRUCTURE_DISRUPTION_FRESHNESS = 72.hours
    INFRASTRUCTURE_DISRUPTION_EVENT_LIMIT = 80
    INFRASTRUCTURE_DISRUPTION_ASSET_LIMITS = {
      airport: 3,
      military_base: 3,
      port: 4,
      power_plant: 4,
      submarine_cable: 4,
    }.freeze
    INFRASTRUCTURE_KINETIC_EVENT_TYPES = %w[
      airstrike
      attack
      drone_attack
      explosion
      missile_attack
      shelling
      strike
    ].freeze
    INFRASTRUCTURE_DISRUPTION_NATURAL_EVENT_CATEGORIES = [
      "Floods",
      "Severe Storms",
      "Volcanoes",
      "Wildfires",
    ].freeze
    LIVE_SHIP_WINDOW = 45.minutes
    RECENT_SHIP_WINDOW = 12.hours
    LIVE_FLIGHT_WINDOW = 45.minutes
    RECENT_FLIGHT_WINDOW = 12.hours
    LIVE_JAMMING_WINDOW = 90.minutes
    RECENT_JAMMING_WINDOW = 18.hours
    LIVE_NOTAM_WINDOW = 18.hours
    RECENT_NOTAM_WINDOW = 36.hours
    FLIGHT_THEATER_RADIUS_KM = 250.0
    FLIGHT_STRATEGIC_ASSET_RADIUS_KM = 120.0
    CHOKEPOINT_SHIP_DISTANCE_MIN_KM = 120.0
    CHOKEPOINT_SHIP_DISTANCE_MAX_KM = 280.0
    SHIP_CABLE_DISTANCE_KM = 10.0
    JAMMING_SIGNAL_DISTANCE_KM = 150.0
    OPERATIONAL_NOTAM_REASONS = ["Security", "TFR", "Military", "VIP Movement"].freeze
    CAMERA_ENTITY_TYPE = "asset".freeze
    CAMERA_CORROBORATION_EVENT_TYPES = %w[flood storm wildfire].freeze
    CAMERA_CORROBORATION_RADIUS_KM = 20.0
    CAMERA_CORROBORATION_LIMIT = 3
    CAMERA_CORROBORATION_WINDOW = 72.hours
    CAMERA_CORROBORATION_MAX_AGE = 24.hours
  end
end
