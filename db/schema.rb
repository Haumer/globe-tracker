# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_04_07_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "airports", force: :cascade do |t|
    t.string "icao_code", null: false
    t.string "iata_code"
    t.string "name", null: false
    t.string "airport_type", null: false
    t.float "latitude", null: false
    t.float "longitude", null: false
    t.integer "elevation_ft"
    t.string "country_code"
    t.string "municipality"
    t.boolean "is_military", default: false, null: false
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["airport_type"], name: "index_airports_on_airport_type"
    t.index ["country_code"], name: "index_airports_on_country_code"
    t.index ["iata_code"], name: "index_airports_on_iata_code"
    t.index ["icao_code"], name: "index_airports_on_icao_code", unique: true
    t.index ["is_military"], name: "index_airports_on_is_military"
    t.index ["latitude", "longitude"], name: "index_airports_on_latitude_and_longitude"
  end

  create_table "alerts", force: :cascade do |t|
    t.bigint "watch_id"
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.jsonb "details", default: {}
    t.string "entity_type"
    t.string "entity_id"
    t.float "lat"
    t.float "lng"
    t.boolean "seen", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "seen", "created_at"], name: "index_alerts_on_user_id_and_seen_and_created_at"
    t.index ["user_id"], name: "index_alerts_on_user_id"
    t.index ["watch_id"], name: "index_alerts_on_watch_id"
  end

  create_table "area_workspaces", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "scope_type", null: false
    t.jsonb "bounds", default: {}, null: false
    t.jsonb "scope_metadata", default: {}, null: false
    t.string "profile", default: "general", null: false
    t.jsonb "default_layers", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["profile"], name: "index_area_workspaces_on_profile"
    t.index ["scope_type"], name: "index_area_workspaces_on_scope_type"
    t.index ["user_id", "updated_at"], name: "index_area_workspaces_on_user_id_and_updated_at"
    t.index ["user_id"], name: "index_area_workspaces_on_user_id"
  end

  create_table "cameras", force: :cascade do |t|
    t.string "webcam_id", null: false
    t.string "source", null: false
    t.string "title"
    t.float "latitude", null: false
    t.float "longitude", null: false
    t.string "status", default: "active"
    t.string "camera_type"
    t.boolean "is_live", default: false
    t.string "player_url"
    t.string "image_url"
    t.string "preview_url"
    t.string "city"
    t.string "region"
    t.string "country"
    t.string "video_id"
    t.string "channel_title"
    t.integer "view_count"
    t.jsonb "metadata", default: {}
    t.datetime "last_checked_at"
    t.datetime "fetched_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_cameras_on_expires_at"
    t.index ["fetched_at"], name: "index_cameras_on_fetched_at"
    t.index ["latitude", "longitude"], name: "idx_cameras_geo"
    t.index ["source"], name: "index_cameras_on_source"
    t.index ["status"], name: "index_cameras_on_status"
    t.index ["webcam_id", "source"], name: "idx_cameras_dedup", unique: true
  end

  create_table "commodity_prices", force: :cascade do |t|
    t.string "symbol", null: false
    t.string "category", null: false
    t.string "name", null: false
    t.decimal "price", precision: 15, scale: 4
    t.decimal "change_pct", precision: 8, scale: 4
    t.string "unit"
    t.float "latitude"
    t.float "longitude"
    t.string "region"
    t.datetime "recorded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source"
    t.index ["category"], name: "index_commodity_prices_on_category"
    t.index ["recorded_at"], name: "index_commodity_prices_on_recorded_at"
    t.index ["source"], name: "index_commodity_prices_on_source"
    t.index ["symbol", "recorded_at"], name: "index_commodity_prices_on_symbol_and_recorded_at", unique: true
  end

  create_table "conflict_events", force: :cascade do |t|
    t.integer "external_id", null: false
    t.string "conflict_name"
    t.string "side_a"
    t.string "side_b"
    t.string "country"
    t.string "region"
    t.string "where_description"
    t.float "latitude", null: false
    t.float "longitude", null: false
    t.date "date_start"
    t.date "date_end"
    t.integer "best_estimate", default: 0
    t.integer "deaths_a", default: 0
    t.integer "deaths_b", default: 0
    t.integer "deaths_civilians", default: 0
    t.integer "type_of_violence"
    t.string "source_headline"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["date_start"], name: "index_conflict_events_on_date_start"
    t.index ["external_id"], name: "index_conflict_events_on_external_id", unique: true
    t.index ["latitude", "longitude"], name: "index_conflict_events_on_latitude_and_longitude"
    t.index ["type_of_violence"], name: "index_conflict_events_on_type_of_violence"
  end

  create_table "country_chokepoint_exposures", force: :cascade do |t|
    t.string "country_code"
    t.string "country_code_alpha3", null: false
    t.string "country_name", null: false
    t.string "commodity_key", null: false
    t.string "commodity_name"
    t.string "chokepoint_key", null: false
    t.string "chokepoint_name", null: false
    t.decimal "exposure_score", precision: 10, scale: 6
    t.decimal "dependency_score", precision: 10, scale: 6
    t.decimal "supplier_share_pct", precision: 10, scale: 4
    t.text "rationale"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_code"], name: "index_country_chokepoint_exposures_on_country_code"
    t.index ["country_code_alpha3", "commodity_key", "chokepoint_key"], name: "idx_country_chokepoint_exposures_unique_chokepoint", unique: true
    t.index ["exposure_score"], name: "index_country_chokepoint_exposures_on_exposure_score"
    t.index ["fetched_at"], name: "index_country_chokepoint_exposures_on_fetched_at"
  end

  create_table "country_commodity_dependencies", force: :cascade do |t|
    t.string "country_code"
    t.string "country_code_alpha3", null: false
    t.string "country_name", null: false
    t.string "commodity_key", null: false
    t.string "commodity_name"
    t.date "period_start"
    t.date "period_end"
    t.string "period_type"
    t.decimal "import_value_usd", precision: 20, scale: 2
    t.integer "supplier_count"
    t.string "top_partner_country_code"
    t.string "top_partner_country_code_alpha3"
    t.string "top_partner_country_name"
    t.decimal "top_partner_share_pct", precision: 10, scale: 4
    t.decimal "concentration_hhi", precision: 10, scale: 6
    t.decimal "import_share_gdp_pct", precision: 10, scale: 6
    t.decimal "dependency_score", precision: 10, scale: 6
    t.jsonb "metadata", default: {}, null: false
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_code"], name: "index_country_commodity_dependencies_on_country_code"
    t.index ["country_code_alpha3", "commodity_key"], name: "idx_country_commodity_dependencies_unique_commodity", unique: true
    t.index ["dependency_score"], name: "index_country_commodity_dependencies_on_dependency_score"
    t.index ["fetched_at"], name: "index_country_commodity_dependencies_on_fetched_at"
  end

  create_table "country_indicator_snapshots", force: :cascade do |t|
    t.string "country_code"
    t.string "country_code_alpha3", null: false
    t.string "country_name", null: false
    t.string "indicator_key", null: false
    t.string "indicator_name", null: false
    t.string "period_type", default: "year", null: false
    t.date "period_start", null: false
    t.date "period_end"
    t.decimal "value_numeric", precision: 20, scale: 6
    t.string "value_text"
    t.string "unit"
    t.string "source", null: false
    t.string "dataset", null: false
    t.string "series_key"
    t.string "release_version"
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_code"], name: "index_country_indicator_snapshots_on_country_code"
    t.index ["country_code_alpha3", "indicator_key", "period_type", "period_start", "dataset"], name: "idx_country_indicator_snapshots_unique_period", unique: true
    t.index ["country_code_alpha3"], name: "index_country_indicator_snapshots_on_country_code_alpha3"
    t.index ["fetched_at"], name: "index_country_indicator_snapshots_on_fetched_at"
    t.index ["indicator_key"], name: "index_country_indicator_snapshots_on_indicator_key"
  end

  create_table "country_profiles", force: :cascade do |t|
    t.string "country_code"
    t.string "country_code_alpha3", null: false
    t.string "country_name", null: false
    t.integer "latest_year"
    t.decimal "gdp_nominal_usd", precision: 20, scale: 2
    t.decimal "gdp_per_capita_usd", precision: 20, scale: 2
    t.decimal "population_total", precision: 20
    t.decimal "imports_goods_services_pct_gdp", precision: 10, scale: 4
    t.decimal "exports_goods_services_pct_gdp", precision: 10, scale: 4
    t.decimal "energy_imports_net_pct_energy_use", precision: 10, scale: 4
    t.jsonb "metadata", default: {}, null: false
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_code"], name: "index_country_profiles_on_country_code"
    t.index ["country_code_alpha3"], name: "index_country_profiles_on_country_code_alpha3", unique: true
    t.index ["fetched_at"], name: "index_country_profiles_on_fetched_at"
  end

  create_table "country_sector_profiles", force: :cascade do |t|
    t.string "country_code"
    t.string "country_code_alpha3", null: false
    t.string "country_name", null: false
    t.string "sector_key", null: false
    t.string "sector_name", null: false
    t.integer "period_year", null: false
    t.decimal "share_pct", precision: 10, scale: 4
    t.integer "rank"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_code"], name: "index_country_sector_profiles_on_country_code"
    t.index ["country_code_alpha3", "sector_key"], name: "idx_country_sector_profiles_unique_sector", unique: true
    t.index ["fetched_at"], name: "index_country_sector_profiles_on_fetched_at"
    t.index ["rank"], name: "index_country_sector_profiles_on_rank"
  end

  create_table "country_sector_snapshots", force: :cascade do |t|
    t.string "country_code"
    t.string "country_code_alpha3", null: false
    t.string "country_name", null: false
    t.string "sector_key", null: false
    t.string "sector_name", null: false
    t.string "metric_key", null: false
    t.string "metric_name", null: false
    t.integer "period_year", null: false
    t.decimal "value_numeric", precision: 20, scale: 6
    t.string "unit"
    t.string "source", null: false
    t.string "dataset", null: false
    t.string "release_version"
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_code"], name: "index_country_sector_snapshots_on_country_code"
    t.index ["country_code_alpha3", "sector_key", "metric_key", "period_year", "dataset"], name: "idx_country_sector_snapshots_unique_period", unique: true
    t.index ["country_code_alpha3"], name: "index_country_sector_snapshots_on_country_code_alpha3"
    t.index ["fetched_at"], name: "index_country_sector_snapshots_on_fetched_at"
    t.index ["sector_key"], name: "index_country_sector_snapshots_on_sector_key"
  end

  create_table "earthquakes", force: :cascade do |t|
    t.string "external_id"
    t.string "title"
    t.float "magnitude"
    t.string "magnitude_type"
    t.float "latitude"
    t.float "longitude"
    t.float "depth"
    t.datetime "event_time"
    t.string "url"
    t.boolean "tsunami"
    t.string "alert"
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_time"], name: "index_earthquakes_on_event_time"
    t.index ["external_id"], name: "index_earthquakes_on_external_id", unique: true
    t.index ["fetched_at"], name: "index_earthquakes_on_fetched_at"
  end

  create_table "energy_balance_snapshots", force: :cascade do |t|
    t.string "country_code"
    t.string "country_code_alpha3", null: false
    t.string "country_name", null: false
    t.string "commodity_key", null: false
    t.string "metric_key", null: false
    t.string "period_type", default: "month", null: false
    t.date "period_start", null: false
    t.date "period_end"
    t.decimal "value_numeric", precision: 20, scale: 6
    t.string "unit"
    t.string "source", null: false
    t.string "dataset", null: false
    t.string "release_version"
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["commodity_key"], name: "index_energy_balance_snapshots_on_commodity_key"
    t.index ["country_code"], name: "index_energy_balance_snapshots_on_country_code"
    t.index ["country_code_alpha3", "commodity_key", "metric_key", "period_type", "period_start", "dataset"], name: "idx_energy_balance_snapshots_unique_period", unique: true
    t.index ["country_code_alpha3"], name: "index_energy_balance_snapshots_on_country_code_alpha3"
    t.index ["fetched_at"], name: "index_energy_balance_snapshots_on_fetched_at"
  end

  create_table "fire_hotspots", force: :cascade do |t|
    t.string "external_id", null: false
    t.float "latitude", null: false
    t.float "longitude", null: false
    t.float "brightness"
    t.string "confidence"
    t.string "satellite"
    t.string "instrument"
    t.float "frp"
    t.float "bright_t31"
    t.string "daynight"
    t.datetime "acq_datetime"
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["acq_datetime"], name: "index_fire_hotspots_on_acq_datetime"
    t.index ["external_id"], name: "index_fire_hotspots_on_external_id", unique: true
    t.index ["latitude", "longitude"], name: "index_fire_hotspots_on_latitude_and_longitude"
  end

  create_table "flight_routes", force: :cascade do |t|
    t.string "callsign", null: false
    t.string "flight_icao24"
    t.string "operator_iata"
    t.string "flight_number"
    t.jsonb "route", default: [], null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.string "error_code"
    t.datetime "fetched_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["callsign"], name: "index_flight_routes_on_callsign", unique: true
    t.index ["expires_at"], name: "index_flight_routes_on_expires_at"
    t.index ["flight_icao24"], name: "index_flight_routes_on_flight_icao24"
    t.index ["status"], name: "index_flight_routes_on_status"
  end

  create_table "flights", force: :cascade do |t|
    t.string "callsign"
    t.float "latitude"
    t.float "longitude"
    t.float "altitude"
    t.float "heading"
    t.float "speed"
    t.string "origin_country"
    t.boolean "on_ground"
    t.string "icao24"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "vertical_rate"
    t.integer "time_position"
    t.string "source"
    t.string "registration"
    t.string "aircraft_type"
    t.integer "nac_p"
    t.boolean "military", default: false, null: false
    t.string "squawk"
    t.string "emergency"
    t.string "category"
    t.float "indicated_airspeed"
    t.float "true_airspeed"
    t.float "mach"
    t.float "mag_heading"
    t.float "true_heading"
    t.float "roll"
    t.float "track_rate"
    t.float "nav_qnh"
    t.integer "nav_altitude_mcp"
    t.integer "nav_altitude_fms"
    t.integer "wind_direction"
    t.integer "wind_speed"
    t.integer "outside_air_temp"
    t.float "signal_strength"
    t.string "message_type"
    t.index ["icao24"], name: "index_flights_on_icao24", unique: true
    t.index ["source", "updated_at"], name: "idx_flights_source_updated"
  end

  create_table "geoconfirmed_events", force: :cascade do |t|
    t.string "external_id", null: false
    t.string "map_region", null: false
    t.string "folder_path"
    t.string "title"
    t.text "description"
    t.float "latitude", null: false
    t.float "longitude", null: false
    t.datetime "event_time"
    t.string "icon_key"
    t.text "source_urls", default: [], array: true
    t.text "geolocation_urls", default: [], array: true
    t.datetime "fetched_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "posted_at"
    t.index ["event_time"], name: "index_geoconfirmed_events_on_event_time"
    t.index ["external_id"], name: "index_geoconfirmed_events_on_external_id", unique: true
    t.index ["fetched_at"], name: "index_geoconfirmed_events_on_fetched_at"
    t.index ["latitude", "longitude"], name: "index_geoconfirmed_events_on_latitude_and_longitude"
    t.index ["map_region"], name: "index_geoconfirmed_events_on_map_region"
    t.index ["posted_at"], name: "index_geoconfirmed_events_on_posted_at"
  end

  create_table "gps_jamming_snapshots", force: :cascade do |t|
    t.float "cell_lat"
    t.float "cell_lng"
    t.integer "total"
    t.integer "bad"
    t.float "percentage"
    t.string "level"
    t.datetime "recorded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cell_lat", "cell_lng", "recorded_at"], name: "idx_gps_jam_cell_time", order: { recorded_at: :desc }
    t.index ["cell_lat", "cell_lng", "recorded_at"], name: "idx_jamming_cell_time"
    t.index ["recorded_at"], name: "index_gps_jamming_snapshots_on_recorded_at"
  end

  create_table "internet_attack_pair_snapshots", force: :cascade do |t|
    t.string "origin_country_code", null: false
    t.string "target_country_code", null: false
    t.string "origin_country_name"
    t.string "target_country_name"
    t.float "attack_pct"
    t.datetime "recorded_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["origin_country_code", "target_country_code", "recorded_at"], name: "idx_attack_pair_snapshots_route_time"
    t.index ["recorded_at"], name: "index_internet_attack_pair_snapshots_on_recorded_at"
  end

  create_table "internet_outages", force: :cascade do |t|
    t.string "external_id"
    t.string "entity_type"
    t.string "entity_code"
    t.string "entity_name"
    t.string "datasource"
    t.float "score"
    t.string "level"
    t.string "condition"
    t.datetime "started_at"
    t.datetime "ended_at"
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_type", "entity_code", "started_at"], name: "idx_outages_entity_time"
    t.index ["external_id"], name: "index_internet_outages_on_external_id", unique: true
    t.index ["fetched_at"], name: "index_internet_outages_on_fetched_at"
    t.index ["started_at"], name: "index_internet_outages_on_started_at"
  end

  create_table "internet_traffic_snapshots", force: :cascade do |t|
    t.string "country_code", null: false
    t.string "country_name"
    t.float "traffic_pct"
    t.float "attack_origin_pct"
    t.float "attack_target_pct"
    t.datetime "recorded_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_code", "recorded_at"], name: "idx_on_country_code_recorded_at_4ce32fcec1"
    t.index ["recorded_at"], name: "index_internet_traffic_snapshots_on_recorded_at"
  end

  create_table "investigation_case_notes", force: :cascade do |t|
    t.bigint "investigation_case_id", null: false
    t.bigint "user_id", null: false
    t.text "body", null: false
    t.string "kind", default: "note", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["investigation_case_id", "created_at"], name: "idx_case_notes_case_created_at"
    t.index ["investigation_case_id"], name: "index_investigation_case_notes_on_investigation_case_id"
    t.index ["user_id"], name: "index_investigation_case_notes_on_user_id"
  end

  create_table "investigation_case_objects", force: :cascade do |t|
    t.bigint "investigation_case_id", null: false
    t.string "object_kind", null: false
    t.string "object_identifier", null: false
    t.string "title", null: false
    t.text "summary"
    t.string "object_type"
    t.float "latitude"
    t.float "longitude"
    t.jsonb "source_context", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["investigation_case_id", "created_at"], name: "idx_case_objects_case_created_at"
    t.index ["investigation_case_id", "object_kind", "object_identifier"], name: "idx_case_objects_unique_object", unique: true
    t.index ["investigation_case_id"], name: "index_investigation_case_objects_on_investigation_case_id"
  end

  create_table "investigation_cases", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.text "summary"
    t.string "status", default: "open", null: false
    t.string "severity", default: "medium", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "assignee_id"
    t.index ["assignee_id"], name: "index_investigation_cases_on_assignee_id"
    t.index ["user_id", "status"], name: "index_investigation_cases_on_user_id_and_status"
    t.index ["user_id", "updated_at"], name: "index_investigation_cases_on_user_id_and_updated_at"
    t.index ["user_id"], name: "index_investigation_cases_on_user_id"
  end

  create_table "layer_snapshots", force: :cascade do |t|
    t.string "snapshot_type", null: false
    t.string "scope_key", default: "global", null: false
    t.string "status", default: "ready", null: false
    t.string "error_code"
    t.jsonb "payload", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "fetched_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_layer_snapshots_on_expires_at"
    t.index ["snapshot_type", "scope_key"], name: "index_layer_snapshots_on_snapshot_type_and_scope_key", unique: true
    t.index ["status"], name: "index_layer_snapshots_on_status"
  end

  create_table "military_bases", force: :cascade do |t|
    t.string "external_id", null: false
    t.string "name"
    t.string "base_type"
    t.string "country"
    t.string "operator"
    t.float "latitude", null: false
    t.float "longitude", null: false
    t.string "source"
    t.jsonb "metadata", default: {}
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_military_bases_on_external_id", unique: true
    t.index ["latitude", "longitude"], name: "index_military_bases_on_latitude_and_longitude"
  end

  create_table "natural_events", force: :cascade do |t|
    t.string "external_id"
    t.string "title"
    t.string "category_id"
    t.string "category_title"
    t.float "latitude"
    t.float "longitude"
    t.datetime "event_date"
    t.float "magnitude_value"
    t.string "magnitude_unit"
    t.string "link"
    t.jsonb "sources"
    t.jsonb "geometry_points"
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_date"], name: "index_natural_events_on_event_date"
    t.index ["external_id"], name: "index_natural_events_on_external_id", unique: true
    t.index ["fetched_at"], name: "index_natural_events_on_fetched_at"
  end

  create_table "news_actors", force: :cascade do |t|
    t.string "canonical_key", null: false
    t.string "name", null: false
    t.string "actor_type", null: false
    t.string "country_code"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_type"], name: "index_news_actors_on_actor_type"
    t.index ["canonical_key"], name: "index_news_actors_on_canonical_key", unique: true
    t.index ["country_code"], name: "index_news_actors_on_country_code"
  end

  create_table "news_articles", force: :cascade do |t|
    t.bigint "news_source_id", null: false
    t.bigint "news_ingest_id"
    t.string "url", null: false
    t.string "canonical_url", null: false
    t.string "title"
    t.text "summary"
    t.string "publisher_name"
    t.string "publisher_domain"
    t.string "language"
    t.datetime "published_at"
    t.datetime "fetched_at"
    t.string "normalization_status", default: "normalized", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "content_scope", default: "adjacent", null: false
    t.string "scope_reason"
    t.string "hydration_status", default: "not_requested", null: false
    t.integer "hydration_attempts", default: 0, null: false
    t.datetime "hydration_last_attempted_at"
    t.datetime "hydrated_at"
    t.string "hydration_error"
    t.string "origin_source_name"
    t.string "origin_source_kind"
    t.string "origin_source_domain"
    t.index ["canonical_url"], name: "index_news_articles_on_canonical_url", unique: true
    t.index ["content_scope"], name: "index_news_articles_on_content_scope"
    t.index ["hydrated_at"], name: "index_news_articles_on_hydrated_at"
    t.index ["hydration_status"], name: "index_news_articles_on_hydration_status"
    t.index ["news_ingest_id"], name: "index_news_articles_on_news_ingest_id"
    t.index ["news_source_id"], name: "index_news_articles_on_news_source_id"
    t.index ["origin_source_domain"], name: "index_news_articles_on_origin_source_domain"
    t.index ["origin_source_kind"], name: "index_news_articles_on_origin_source_kind"
    t.index ["published_at"], name: "index_news_articles_on_published_at"
    t.index ["publisher_domain"], name: "index_news_articles_on_publisher_domain"
  end

  create_table "news_claim_actors", force: :cascade do |t|
    t.bigint "news_claim_id", null: false
    t.bigint "news_actor_id", null: false
    t.string "role", null: false
    t.integer "position", null: false
    t.float "confidence"
    t.string "matched_text"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["news_actor_id"], name: "index_news_claim_actors_on_news_actor_id"
    t.index ["news_claim_id", "news_actor_id", "role"], name: "idx_news_claim_actors_unique_role", unique: true
    t.index ["news_claim_id", "position"], name: "idx_news_claim_actors_unique_position", unique: true
    t.index ["news_claim_id"], name: "index_news_claim_actors_on_news_claim_id"
  end

  create_table "news_claims", force: :cascade do |t|
    t.bigint "news_article_id", null: false
    t.string "event_type", null: false
    t.text "claim_text"
    t.float "confidence"
    t.string "extraction_method", default: "heuristic", null: false
    t.string "extraction_version", default: "headline_rules_v1", null: false
    t.datetime "published_at"
    t.boolean "primary", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "event_family", default: "general", null: false
    t.float "extraction_confidence", default: 0.0, null: false
    t.float "actor_confidence", default: 0.0, null: false
    t.float "event_confidence", default: 0.0, null: false
    t.float "geo_confidence", default: 0.0, null: false
    t.float "source_reliability", default: 0.0, null: false
    t.string "verification_status", default: "unverified", null: false
    t.string "geo_precision", default: "unknown", null: false
    t.jsonb "provenance", default: {}, null: false
    t.index ["event_family"], name: "index_news_claims_on_event_family"
    t.index ["event_type"], name: "index_news_claims_on_event_type"
    t.index ["geo_precision"], name: "index_news_claims_on_geo_precision"
    t.index ["news_article_id"], name: "index_news_claims_on_news_article_id", unique: true
    t.index ["published_at"], name: "index_news_claims_on_published_at"
    t.index ["verification_status"], name: "index_news_claims_on_verification_status"
  end

  create_table "news_events", force: :cascade do |t|
    t.string "url"
    t.string "name"
    t.float "latitude"
    t.float "longitude"
    t.float "tone"
    t.string "level"
    t.string "category"
    t.jsonb "themes"
    t.datetime "published_at"
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source"
    t.string "title"
    t.string "credibility"
    t.string "threat_level"
    t.string "story_cluster_id"
    t.boolean "ai_enriched", default: false
    t.bigint "news_ingest_id"
    t.bigint "news_source_id"
    t.bigint "news_article_id"
    t.string "content_scope"
    t.index ["ai_enriched"], name: "index_news_events_on_ai_enriched"
    t.index ["category"], name: "index_news_events_on_category"
    t.index ["content_scope"], name: "index_news_events_on_content_scope"
    t.index ["fetched_at"], name: "index_news_events_on_fetched_at"
    t.index ["news_article_id"], name: "index_news_events_on_news_article_id"
    t.index ["news_ingest_id"], name: "index_news_events_on_news_ingest_id"
    t.index ["news_source_id"], name: "index_news_events_on_news_source_id"
    t.index ["published_at", "story_cluster_id"], name: "idx_news_published_cluster"
    t.index ["published_at"], name: "index_news_events_on_published_at"
    t.index ["source"], name: "index_news_events_on_source"
    t.index ["story_cluster_id"], name: "index_news_events_on_story_cluster_id"
    t.index ["title"], name: "index_news_events_on_title"
    t.index ["url"], name: "index_news_events_on_url", unique: true
  end

  create_table "news_ingests", force: :cascade do |t|
    t.string "source_feed", null: false
    t.string "source_endpoint_url", null: false
    t.string "external_id"
    t.string "raw_url"
    t.text "raw_title"
    t.text "raw_summary"
    t.datetime "raw_published_at"
    t.datetime "fetched_at", null: false
    t.string "payload_format", null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.integer "http_status"
    t.string "content_hash", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["content_hash"], name: "index_news_ingests_on_content_hash", unique: true
    t.index ["fetched_at"], name: "index_news_ingests_on_fetched_at"
    t.index ["source_feed"], name: "index_news_ingests_on_source_feed"
  end

  create_table "news_sources", force: :cascade do |t|
    t.string "canonical_key", null: false
    t.string "name", null: false
    t.string "source_kind", default: "publisher", null: false
    t.string "publisher_domain"
    t.string "publisher_country"
    t.string "publisher_city"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["canonical_key"], name: "index_news_sources_on_canonical_key", unique: true
    t.index ["publisher_domain"], name: "index_news_sources_on_publisher_domain"
    t.index ["source_kind"], name: "index_news_sources_on_source_kind"
  end

  create_table "news_story_clusters", force: :cascade do |t|
    t.string "cluster_key", null: false
    t.string "canonical_title"
    t.string "content_scope", default: "adjacent", null: false
    t.string "event_family", null: false
    t.string "event_type", null: false
    t.string "location_name"
    t.float "latitude"
    t.float "longitude"
    t.string "geo_precision", default: "unknown", null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.integer "article_count", default: 0, null: false
    t.integer "source_count", default: 0, null: false
    t.float "cluster_confidence", default: 0.0, null: false
    t.string "verification_status", default: "single_source", null: false
    t.bigint "lead_news_article_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "source_reliability", default: 0.0, null: false
    t.float "geo_confidence", default: 0.0, null: false
    t.jsonb "provenance", default: {}, null: false
    t.index ["cluster_key"], name: "index_news_story_clusters_on_cluster_key", unique: true
    t.index ["content_scope", "last_seen_at"], name: "index_news_story_clusters_on_content_scope_and_last_seen_at"
    t.index ["event_family", "last_seen_at"], name: "index_news_story_clusters_on_event_family_and_last_seen_at"
    t.index ["lead_news_article_id"], name: "index_news_story_clusters_on_lead_news_article_id"
  end

  create_table "news_story_memberships", force: :cascade do |t|
    t.bigint "news_story_cluster_id", null: false
    t.bigint "news_article_id", null: false
    t.float "match_score", default: 0.0, null: false
    t.boolean "primary", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["news_article_id"], name: "index_news_story_memberships_on_news_article_id", unique: true
    t.index ["news_story_cluster_id", "primary"], name: "idx_news_story_memberships_cluster_primary"
    t.index ["news_story_cluster_id"], name: "index_news_story_memberships_on_news_story_cluster_id"
  end

  create_table "notams", force: :cascade do |t|
    t.string "external_id", null: false
    t.string "source"
    t.float "latitude"
    t.float "longitude"
    t.float "radius_nm"
    t.integer "radius_m"
    t.integer "alt_low_ft"
    t.integer "alt_high_ft"
    t.string "reason"
    t.string "text"
    t.string "country"
    t.datetime "effective_start"
    t.datetime "effective_end"
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["effective_start"], name: "index_notams_on_effective_start"
    t.index ["external_id"], name: "index_notams_on_external_id", unique: true
    t.index ["fetched_at"], name: "index_notams_on_fetched_at"
    t.index ["latitude", "longitude"], name: "index_notams_on_latitude_and_longitude"
  end

  create_table "ontology_entities", force: :cascade do |t|
    t.string "canonical_key", null: false
    t.string "entity_type", null: false
    t.string "canonical_name", null: false
    t.string "country_code"
    t.bigint "parent_entity_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["canonical_key"], name: "index_ontology_entities_on_canonical_key", unique: true
    t.index ["country_code"], name: "index_ontology_entities_on_country_code"
    t.index ["entity_type"], name: "index_ontology_entities_on_entity_type"
    t.index ["parent_entity_id"], name: "index_ontology_entities_on_parent_entity_id"
  end

  create_table "ontology_entity_aliases", force: :cascade do |t|
    t.bigint "ontology_entity_id", null: false
    t.string "name", null: false
    t.string "alias_type", default: "common", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alias_type"], name: "index_ontology_entity_aliases_on_alias_type"
    t.index ["ontology_entity_id", "name"], name: "idx_ontology_entity_aliases_unique_name", unique: true
    t.index ["ontology_entity_id"], name: "index_ontology_entity_aliases_on_ontology_entity_id"
  end

  create_table "ontology_entity_links", force: :cascade do |t|
    t.bigint "ontology_entity_id", null: false
    t.string "linkable_type", null: false
    t.bigint "linkable_id", null: false
    t.string "role", null: false
    t.float "confidence", default: 1.0, null: false
    t.string "method", default: "sync", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["linkable_type", "linkable_id"], name: "idx_ontology_entity_links_linkable"
    t.index ["ontology_entity_id", "linkable_type", "linkable_id", "role"], name: "idx_ontology_entity_links_unique_role", unique: true
    t.index ["ontology_entity_id"], name: "index_ontology_entity_links_on_ontology_entity_id"
  end

  create_table "ontology_event_entities", force: :cascade do |t|
    t.bigint "ontology_event_id", null: false
    t.bigint "ontology_entity_id", null: false
    t.string "role", null: false
    t.float "confidence", default: 1.0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ontology_entity_id"], name: "index_ontology_event_entities_on_ontology_entity_id"
    t.index ["ontology_event_id", "ontology_entity_id", "role"], name: "idx_ontology_event_entities_unique_role", unique: true
    t.index ["ontology_event_id"], name: "index_ontology_event_entities_on_ontology_event_id"
  end

  create_table "ontology_events", force: :cascade do |t|
    t.string "canonical_key", null: false
    t.string "event_family", null: false
    t.string "event_type", null: false
    t.string "status", default: "active", null: false
    t.bigint "place_entity_id"
    t.bigint "primary_story_cluster_id"
    t.string "verification_status", default: "unverified", null: false
    t.string "geo_precision", default: "unknown", null: false
    t.float "confidence", default: 0.0, null: false
    t.float "source_reliability", default: 0.0, null: false
    t.float "geo_confidence", default: 0.0, null: false
    t.datetime "started_at"
    t.datetime "ended_at"
    t.datetime "first_seen_at"
    t.datetime "last_seen_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["canonical_key"], name: "index_ontology_events_on_canonical_key", unique: true
    t.index ["event_family", "last_seen_at"], name: "index_ontology_events_on_event_family_and_last_seen_at"
    t.index ["place_entity_id"], name: "index_ontology_events_on_place_entity_id"
    t.index ["primary_story_cluster_id"], name: "index_ontology_events_on_primary_story_cluster_id"
    t.index ["verification_status"], name: "index_ontology_events_on_verification_status"
  end

  create_table "ontology_evidence_links", force: :cascade do |t|
    t.bigint "ontology_event_id", null: false
    t.string "evidence_type", null: false
    t.bigint "evidence_id", null: false
    t.string "evidence_role", default: "supporting", null: false
    t.float "confidence", default: 1.0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["evidence_type", "evidence_id"], name: "idx_ontology_evidence_links_evidence"
    t.index ["ontology_event_id", "evidence_type", "evidence_id", "evidence_role"], name: "idx_ontology_evidence_links_unique_role", unique: true
    t.index ["ontology_event_id"], name: "index_ontology_evidence_links_on_ontology_event_id"
  end

  create_table "ontology_relationship_evidences", force: :cascade do |t|
    t.bigint "ontology_relationship_id", null: false
    t.string "evidence_type", null: false
    t.bigint "evidence_id", null: false
    t.string "evidence_role", default: "supporting", null: false
    t.float "confidence", default: 1.0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["evidence_type", "evidence_id"], name: "idx_ontology_relationship_evidences_lookup"
    t.index ["ontology_relationship_id", "evidence_type", "evidence_id", "evidence_role"], name: "idx_ontology_relationship_evidences_unique_role", unique: true
    t.index ["ontology_relationship_id"], name: "idx_on_ontology_relationship_id_bffc68baf7"
  end

  create_table "ontology_relationships", force: :cascade do |t|
    t.string "source_node_type", null: false
    t.bigint "source_node_id", null: false
    t.string "target_node_type", null: false
    t.bigint "target_node_id", null: false
    t.string "relation_type", null: false
    t.float "confidence", default: 0.0, null: false
    t.datetime "fresh_until"
    t.string "derived_by", default: "sync", null: false
    t.text "explanation"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fresh_until"], name: "index_ontology_relationships_on_fresh_until"
    t.index ["source_node_type", "source_node_id", "target_node_type", "target_node_id", "relation_type"], name: "idx_ontology_relationships_unique_type", unique: true
    t.index ["source_node_type", "source_node_id"], name: "idx_ontology_relationships_source"
    t.index ["target_node_type", "target_node_id"], name: "idx_ontology_relationships_target"
  end

  create_table "pipelines", force: :cascade do |t|
    t.string "pipeline_id"
    t.string "name"
    t.string "pipeline_type"
    t.string "status"
    t.float "length_km"
    t.jsonb "coordinates"
    t.string "color"
    t.string "country"
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pipeline_id"], name: "index_pipelines_on_pipeline_id", unique: true
  end

  create_table "polling_stats", force: :cascade do |t|
    t.string "source", null: false
    t.string "poll_type", null: false
    t.integer "records_fetched", default: 0
    t.integer "records_stored", default: 0
    t.integer "duration_ms", default: 0
    t.string "status", null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_polling_stats_on_created_at"
    t.index ["source"], name: "index_polling_stats_on_source"
  end

  create_table "position_snapshots", force: :cascade do |t|
    t.string "entity_type", null: false
    t.string "entity_id", null: false
    t.string "callsign"
    t.float "latitude", null: false
    t.float "longitude", null: false
    t.float "altitude"
    t.float "heading"
    t.float "speed"
    t.float "vertical_rate"
    t.boolean "on_ground"
    t.string "extra"
    t.datetime "recorded_at", null: false
    t.index ["entity_type", "entity_id", "recorded_at"], name: "idx_position_snapshots_entity_lookup", order: { recorded_at: :desc }
    t.index ["entity_type", "entity_id", "recorded_at"], name: "idx_snapshots_entity_time"
    t.index ["entity_type", "recorded_at"], name: "index_position_snapshots_on_entity_type_and_recorded_at"
    t.index ["recorded_at"], name: "index_position_snapshots_on_recorded_at"
  end

  create_table "power_plants", force: :cascade do |t|
    t.string "gppd_idnr", null: false
    t.string "name", null: false
    t.string "country_code"
    t.string "country_name"
    t.float "latitude", null: false
    t.float "longitude", null: false
    t.float "capacity_mw"
    t.string "primary_fuel"
    t.string "other_fuel"
    t.string "owner"
    t.integer "commissioning_year"
    t.string "source"
    t.string "url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gppd_idnr"], name: "index_power_plants_on_gppd_idnr", unique: true
    t.index ["latitude", "longitude"], name: "index_power_plants_on_latitude_and_longitude"
    t.index ["primary_fuel"], name: "index_power_plants_on_primary_fuel"
  end

  create_table "railways", force: :cascade do |t|
    t.integer "category", default: 0
    t.integer "electrified", default: 0
    t.string "continent"
    t.float "min_lat"
    t.float "max_lat"
    t.float "min_lng"
    t.float "max_lng"
    t.jsonb "coordinates", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["continent"], name: "index_railways_on_continent"
    t.index ["min_lat", "max_lat", "min_lng", "max_lng"], name: "idx_railways_bbox"
  end

  create_table "satellite_tle_snapshots", force: :cascade do |t|
    t.integer "norad_id", null: false
    t.string "name"
    t.string "tle_line1", null: false
    t.string "tle_line2", null: false
    t.string "category"
    t.datetime "recorded_at", null: false
    t.index ["norad_id", "recorded_at"], name: "idx_tle_snapshots_lookup", order: { recorded_at: :desc }
    t.index ["recorded_at"], name: "idx_tle_snapshots_recorded_at"
  end

  create_table "satellites", force: :cascade do |t|
    t.string "name"
    t.string "tle_line1"
    t.string "tle_line2"
    t.string "category"
    t.integer "norad_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "operator"
    t.string "mission_type"
    t.string "country_owner"
    t.string "users"
    t.string "purpose"
    t.string "detailed_purpose"
    t.string "orbit_class"
    t.string "launch_date"
    t.string "launch_site"
    t.string "launch_vehicle"
    t.string "contractor"
    t.string "expected_lifetime"
    t.index ["norad_id"], name: "index_satellites_on_norad_id", unique: true
  end

  create_table "sector_input_profiles", force: :cascade do |t|
    t.string "scope_key", default: "global", null: false
    t.string "country_code"
    t.string "country_code_alpha3"
    t.string "country_name"
    t.string "sector_key", null: false
    t.string "sector_name", null: false
    t.string "input_kind", null: false
    t.string "input_key", null: false
    t.string "input_name"
    t.integer "period_year", null: false
    t.decimal "coefficient", precision: 20, scale: 8
    t.integer "rank"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_code_alpha3"], name: "index_sector_input_profiles_on_country_code_alpha3"
    t.index ["fetched_at"], name: "index_sector_input_profiles_on_fetched_at"
    t.index ["scope_key", "sector_key", "input_kind", "input_key"], name: "idx_sector_input_profiles_unique_input", unique: true
  end

  create_table "sector_input_snapshots", force: :cascade do |t|
    t.string "scope_key", default: "global", null: false
    t.string "country_code"
    t.string "country_code_alpha3"
    t.string "country_name"
    t.string "sector_key", null: false
    t.string "sector_name", null: false
    t.string "input_kind", null: false
    t.string "input_key", null: false
    t.string "input_name"
    t.decimal "coefficient", precision: 20, scale: 8
    t.integer "period_year", null: false
    t.string "source", null: false
    t.string "dataset", null: false
    t.string "release_version"
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fetched_at"], name: "index_sector_input_snapshots_on_fetched_at"
    t.index ["input_key"], name: "index_sector_input_snapshots_on_input_key"
    t.index ["scope_key", "sector_key", "input_kind", "input_key", "period_year", "dataset"], name: "idx_sector_input_snapshots_unique_period", unique: true
    t.index ["scope_key"], name: "index_sector_input_snapshots_on_scope_key"
    t.index ["sector_key"], name: "index_sector_input_snapshots_on_sector_key"
  end

  create_table "service_runtime_states", force: :cascade do |t|
    t.string "service_name", null: false
    t.string "desired_state", default: "running", null: false
    t.string "reported_state", default: "stopped", null: false
    t.datetime "reported_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["service_name"], name: "index_service_runtime_states_on_service_name", unique: true
  end

  create_table "ships", force: :cascade do |t|
    t.string "mmsi"
    t.string "name"
    t.integer "ship_type"
    t.float "latitude"
    t.float "longitude"
    t.float "speed"
    t.float "heading"
    t.float "course"
    t.string "destination"
    t.string "flag"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["mmsi"], name: "index_ships_on_mmsi", unique: true
    t.index ["updated_at"], name: "idx_ships_updated_at"
  end

  create_table "source_feed_statuses", force: :cascade do |t|
    t.string "feed_key", null: false
    t.string "provider", null: false
    t.string "display_name", null: false
    t.string "feed_kind", null: false
    t.string "endpoint_url"
    t.string "status", default: "unknown", null: false
    t.datetime "last_success_at"
    t.datetime "last_error_at"
    t.integer "last_http_status"
    t.integer "last_records_fetched", default: 0, null: false
    t.integer "last_records_stored", default: 0, null: false
    t.string "last_error_message"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["feed_key"], name: "index_source_feed_statuses_on_feed_key", unique: true
    t.index ["provider"], name: "index_source_feed_statuses_on_provider"
    t.index ["status"], name: "index_source_feed_statuses_on_status"
  end

  create_table "submarine_cables", force: :cascade do |t|
    t.string "cable_id"
    t.string "name"
    t.string "color"
    t.jsonb "coordinates"
    t.jsonb "landing_points"
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cable_id"], name: "index_submarine_cables_on_cable_id", unique: true
  end

  create_table "timeline_events", force: :cascade do |t|
    t.string "event_type", null: false
    t.string "eventable_type", null: false
    t.bigint "eventable_id", null: false
    t.float "latitude"
    t.float "longitude"
    t.datetime "recorded_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type", "recorded_at"], name: "index_timeline_events_on_event_type_and_recorded_at"
    t.index ["eventable_type", "eventable_id"], name: "index_timeline_events_on_eventable_type_and_eventable_id", unique: true
    t.index ["recorded_at"], name: "index_timeline_events_on_recorded_at"
  end

  create_table "trade_flow_snapshots", force: :cascade do |t|
    t.string "reporter_country_code"
    t.string "reporter_country_code_alpha3", null: false
    t.string "reporter_country_name"
    t.string "partner_country_code"
    t.string "partner_country_code_alpha3", null: false
    t.string "partner_country_name"
    t.string "flow_direction", null: false
    t.string "commodity_key", null: false
    t.string "commodity_name"
    t.string "hs_code"
    t.string "period_type", default: "month", null: false
    t.date "period_start", null: false
    t.date "period_end"
    t.decimal "trade_value_usd", precision: 20, scale: 2
    t.decimal "quantity", precision: 20, scale: 4
    t.string "quantity_unit"
    t.string "source", null: false
    t.string "dataset", null: false
    t.string "release_version"
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["commodity_key"], name: "index_trade_flow_snapshots_on_commodity_key"
    t.index ["fetched_at"], name: "index_trade_flow_snapshots_on_fetched_at"
    t.index ["partner_country_code"], name: "index_trade_flow_snapshots_on_partner_country_code"
    t.index ["partner_country_code_alpha3"], name: "index_trade_flow_snapshots_on_partner_country_code_alpha3"
    t.index ["reporter_country_code"], name: "index_trade_flow_snapshots_on_reporter_country_code"
    t.index ["reporter_country_code_alpha3", "partner_country_code_alpha3", "flow_direction", "commodity_key", "hs_code", "period_type", "period_start", "dataset"], name: "idx_trade_flow_snapshots_unique_period", unique: true
    t.index ["reporter_country_code_alpha3"], name: "index_trade_flow_snapshots_on_reporter_country_code_alpha3"
  end

  create_table "trade_locations", force: :cascade do |t|
    t.string "locode", null: false
    t.string "country_code"
    t.string "country_code_alpha3"
    t.string "country_name"
    t.string "subdivision_code"
    t.string "name", null: false
    t.string "normalized_name"
    t.string "location_kind", default: "trade_node", null: false
    t.string "function_codes"
    t.float "latitude"
    t.float "longitude"
    t.string "status", default: "active", null: false
    t.string "source", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_code"], name: "index_trade_locations_on_country_code"
    t.index ["country_code_alpha3"], name: "index_trade_locations_on_country_code_alpha3"
    t.index ["latitude", "longitude"], name: "index_trade_locations_on_latitude_and_longitude"
    t.index ["location_kind"], name: "index_trade_locations_on_location_kind"
    t.index ["locode"], name: "index_trade_locations_on_locode", unique: true
  end

  create_table "train_ingests", force: :cascade do |t|
    t.string "source_key", null: false
    t.string "source_name", null: false
    t.string "status", default: "fetched", null: false
    t.string "error_code"
    t.jsonb "request_metadata", default: {}, null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "fetched_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fetched_at"], name: "index_train_ingests_on_fetched_at"
    t.index ["source_key"], name: "index_train_ingests_on_source_key"
    t.index ["status"], name: "index_train_ingests_on_status"
  end

  create_table "train_observations", force: :cascade do |t|
    t.string "external_id", null: false
    t.bigint "train_ingest_id"
    t.string "source", default: "hafas", null: false
    t.string "operator_key"
    t.string "operator_name"
    t.string "name"
    t.string "category"
    t.string "category_long"
    t.string "flag"
    t.float "latitude"
    t.float "longitude"
    t.string "direction"
    t.integer "progress"
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "fetched_at", null: false
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "matched_railway_id"
    t.float "snapped_latitude"
    t.float "snapped_longitude"
    t.float "snap_distance_m"
    t.string "snap_confidence"
    t.index ["expires_at"], name: "index_train_observations_on_expires_at"
    t.index ["external_id"], name: "index_train_observations_on_external_id", unique: true
    t.index ["fetched_at"], name: "index_train_observations_on_fetched_at"
    t.index ["matched_railway_id"], name: "index_train_observations_on_matched_railway_id"
    t.index ["operator_key"], name: "index_train_observations_on_operator_key"
    t.index ["snap_confidence"], name: "index_train_observations_on_snap_confidence"
    t.index ["train_ingest_id"], name: "index_train_observations_on_train_ingest_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "preferences", default: {}
    t.boolean "admin", default: false, null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "watches", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "watch_type", null: false
    t.jsonb "conditions", default: {}
    t.string "notify_via", default: "in_app"
    t.boolean "active", default: true
    t.datetime "last_triggered_at"
    t.integer "cooldown_minutes", default: 15
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "active"], name: "index_watches_on_user_id_and_active"
    t.index ["user_id"], name: "index_watches_on_user_id"
  end

  create_table "weather_alerts", force: :cascade do |t|
    t.string "external_id", null: false
    t.string "event"
    t.string "severity"
    t.string "urgency"
    t.string "certainty"
    t.string "headline"
    t.text "description"
    t.string "areas"
    t.string "sender"
    t.datetime "onset"
    t.datetime "expires"
    t.float "latitude"
    t.float "longitude"
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_weather_alerts_on_external_id", unique: true
    t.index ["fetched_at"], name: "index_weather_alerts_on_fetched_at"
    t.index ["latitude", "longitude"], name: "index_weather_alerts_on_latitude_and_longitude"
    t.index ["onset"], name: "index_weather_alerts_on_onset"
  end

  create_table "workspaces", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.float "camera_lat"
    t.float "camera_lng"
    t.float "camera_height"
    t.float "camera_heading"
    t.float "camera_pitch"
    t.jsonb "layers", default: {}
    t.jsonb "filters", default: {}
    t.boolean "is_default", default: false
    t.boolean "shared", default: false
    t.string "slug"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_workspaces_on_slug", unique: true
    t.index ["user_id", "is_default"], name: "index_workspaces_on_user_id_and_is_default"
    t.index ["user_id"], name: "index_workspaces_on_user_id"
  end

  add_foreign_key "alerts", "users"
  add_foreign_key "alerts", "watches"
  add_foreign_key "area_workspaces", "users"
  add_foreign_key "investigation_case_notes", "investigation_cases"
  add_foreign_key "investigation_case_notes", "users"
  add_foreign_key "investigation_case_objects", "investigation_cases"
  add_foreign_key "investigation_cases", "users"
  add_foreign_key "investigation_cases", "users", column: "assignee_id"
  add_foreign_key "news_articles", "news_ingests"
  add_foreign_key "news_articles", "news_sources"
  add_foreign_key "news_claim_actors", "news_actors"
  add_foreign_key "news_claim_actors", "news_claims"
  add_foreign_key "news_claims", "news_articles"
  add_foreign_key "news_events", "news_articles"
  add_foreign_key "news_events", "news_ingests"
  add_foreign_key "news_events", "news_sources"
  add_foreign_key "news_story_clusters", "news_articles", column: "lead_news_article_id"
  add_foreign_key "news_story_memberships", "news_articles"
  add_foreign_key "news_story_memberships", "news_story_clusters"
  add_foreign_key "ontology_entities", "ontology_entities", column: "parent_entity_id"
  add_foreign_key "ontology_entity_aliases", "ontology_entities"
  add_foreign_key "ontology_entity_links", "ontology_entities"
  add_foreign_key "ontology_event_entities", "ontology_entities"
  add_foreign_key "ontology_event_entities", "ontology_events"
  add_foreign_key "ontology_events", "news_story_clusters", column: "primary_story_cluster_id"
  add_foreign_key "ontology_events", "ontology_entities", column: "place_entity_id"
  add_foreign_key "ontology_evidence_links", "ontology_events"
  add_foreign_key "ontology_relationship_evidences", "ontology_relationships"
  add_foreign_key "train_observations", "railways", column: "matched_railway_id"
  add_foreign_key "train_observations", "train_ingests"
  add_foreign_key "watches", "users"
  add_foreign_key "workspaces", "users"
end
