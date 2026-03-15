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

ActiveRecord::Schema[7.1].define(version: 2026_03_15_120000) do
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
    t.index ["category"], name: "index_commodity_prices_on_category"
    t.index ["recorded_at"], name: "index_commodity_prices_on_recorded_at"
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
    t.index ["category"], name: "index_news_events_on_category"
    t.index ["fetched_at"], name: "index_news_events_on_fetched_at"
    t.index ["published_at", "story_cluster_id"], name: "idx_news_published_cluster"
    t.index ["published_at"], name: "index_news_events_on_published_at"
    t.index ["source"], name: "index_news_events_on_source"
    t.index ["story_cluster_id"], name: "index_news_events_on_story_cluster_id"
    t.index ["title"], name: "index_news_events_on_title"
    t.index ["url"], name: "index_news_events_on_url", unique: true
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
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
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
  add_foreign_key "watches", "users"
  add_foreign_key "workspaces", "users"
end
