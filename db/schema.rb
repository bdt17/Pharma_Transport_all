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

ActiveRecord::Schema[8.1].define(version: 2025_12_22_002316) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "audit_events", force: :cascade do |t|
    t.string "action"
    t.string "actor"
    t.datetime "created_at", null: false
    t.jsonb "metadata"
    t.integer "resource_id"
    t.datetime "updated_at", null: false
  end

  create_table "controlled_shipments", force: :cascade do |t|
    t.jsonb "chain_of_custody"
    t.datetime "created_at", null: false
    t.string "dea_number"
    t.string "dea_schedule"
    t.boolean "signature_required"
    t.datetime "updated_at", null: false
  end

  create_table "dea_shipments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "drivers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name"
    t.string "phone_number"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_drivers_on_email", unique: true
    t.index ["reset_password_token"], name: "index_drivers_on_reset_password_token", unique: true
  end

  create_table "electronic_signatures", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "document_id"
    t.string "document_type"
    t.string "docusign_envelope_id"
    t.string "signature_hash"
    t.datetime "signed_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_electronic_signatures_on_user_id"
  end

  create_table "geofences", force: :cascade do |t|
    t.string "boundary"
    t.datetime "created_at", null: false
    t.float "latitude"
    t.float "longitude"
    t.string "name"
    t.float "radius"
    t.datetime "updated_at", null: false
  end

  create_table "gps_readings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "latitude"
    t.float "longitude"
    t.float "temperature"
    t.datetime "updated_at", null: false
    t.integer "vehicle_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.string "subdomain"
    t.datetime "updated_at", null: false
  end

  create_table "sensor_readings", force: :cascade do |t|
    t.string "calibration_cert_url"
    t.datetime "created_at", null: false
    t.float "humidity"
    t.boolean "nist_traceable"
    t.jsonb "raw_payload"
    t.string "source"
    t.float "temperature"
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id", null: false
    t.index ["vehicle_id"], name: "index_sensor_readings_on_vehicle_id"
  end

  create_table "signatures", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "document_id"
    t.string "document_type"
    t.string "signature_hash"
    t.string "signature_method"
    t.datetime "signed_at"
    t.datetime "updated_at", null: false
    t.integer "user_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "plan"
    t.decimal "price"
    t.string "status"
    t.datetime "updated_at", null: false
  end

  create_table "transport_anomalies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "detected_at"
    t.boolean "geofence_breach"
    t.string "severity"
    t.boolean "temperature_spike"
    t.boolean "theft_route"
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "vehicles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "latitude"
    t.float "longitude"
    t.string "name"
    t.string "status"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "electronic_signatures", "users"
  add_foreign_key "sensor_readings", "vehicles"
end
