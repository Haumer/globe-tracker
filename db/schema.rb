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

ActiveRecord::Schema[7.1].define(version: 2026_03_11_224743) do
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
    t.index ["icao24"], name: "index_flights_on_icao24", unique: true
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
    t.index ["category"], name: "index_news_events_on_category"
    t.index ["fetched_at"], name: "index_news_events_on_fetched_at"
    t.index ["published_at"], name: "index_news_events_on_published_at"
    t.index ["source"], name: "index_news_events_on_source"
    t.index ["title"], name: "index_news_events_on_title"
    t.index ["url"], name: "index_news_events_on_url", unique: true
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

end
