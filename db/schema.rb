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

ActiveRecord::Schema[7.1].define(version: 2026_03_10_071636) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

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
    t.index ["icao24"], name: "index_flights_on_icao24", unique: true
  end

  create_table "satellites", force: :cascade do |t|
    t.string "name"
    t.string "tle_line1"
    t.string "tle_line2"
    t.string "category"
    t.integer "norad_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

end
