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

ActiveRecord::Schema[8.1].define(version: 2026_05_12_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "beacon_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "origin", limit: 200, null: false
    t.bigint "project_id", null: false
    t.string "version", limit: 100, null: false
    t.index ["created_at"], name: "index_beacon_events_on_created_at"
    t.index ["project_id", "origin", "created_at"], name: "index_beacon_events_on_project_id_and_origin_and_created_at"
    t.index ["project_id"], name: "index_beacon_events_on_project_id"
  end

  create_table "entries", force: :cascade do |t|
    t.text "body_markdown", null: false
    t.jsonb "body_tokens", default: [], null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "version_id", null: false
    t.index ["version_id", "position"], name: "index_entries_on_version_id_and_position"
    t.index ["version_id"], name: "index_entries_on_version_id"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "homepage_url", limit: 500
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index "lower((slug)::text)", name: "index_projects_on_lower_slug", unique: true
    t.index ["user_id"], name: "index_projects_on_user_id"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name"
    t.string "nickname"
    t.string "provider"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true, where: "(provider IS NOT NULL)"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "number", null: false
    t.bigint "project_id", null: false
    t.date "released_at"
    t.datetime "updated_at", null: false
    t.boolean "yanked", default: false, null: false
    t.index ["project_id", "number"], name: "index_versions_on_project_id_and_number", unique: true
    t.index ["project_id", "released_at"], name: "index_versions_on_project_id_and_released_at"
    t.index ["project_id"], name: "index_versions_on_project_id"
    t.index ["project_id"], name: "index_versions_on_project_id_unreleased", unique: true, where: "(released_at IS NULL)"
  end

  add_foreign_key "beacon_events", "projects"
  add_foreign_key "entries", "versions"
  add_foreign_key "projects", "users"
  add_foreign_key "versions", "projects"
end
