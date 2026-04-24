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

ActiveRecord::Schema[8.0].define(version: 2026_04_20_060501) do
  create_schema "topology"

  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "postgis"
  enable_extension "topology.postgis_topology"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "folders", force: :cascade do |t|
    t.string "title", limit: 15, null: false
    t.bigint "parent_id"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_folders_on_created_at"
    t.index ["parent_id"], name: "index_folders_on_parent_id"
    t.index ["user_id", "title", "parent_id"], name: "index_folders_on_user_id_and_title_and_parent_id", unique: true
    t.index ["user_id"], name: "index_folders_on_user_id"
  end

  create_table "media_items", force: :cascade do |t|
    t.bigint "folder_id"
    t.string "ai_classification"
    t.float "ai_confidence"
    t.integer "ai_class_id"
    t.datetime "ai_classified_at"
    t.jsonb "ai_full_results", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_classification"], name: "index_media_items_on_ai_classification"
    t.index ["ai_classified_at"], name: "index_media_items_on_ai_classified_at"
    t.index ["folder_id"], name: "index_media_items_on_folder_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "vineyards", force: :cascade do |t|
    t.string "name", null: false
    t.geography "polygon", limit: {:srid=>4326, :type=>"st_polygon", :geographic=>true}, null: false
    t.string "grape_variety"
    t.integer "planting_year"
    t.bigint "user_id", null: false
    t.decimal "area_hectares", precision: 10, scale: 4
    t.integer "total_rows", default: 0, null: false
    t.integer "total_bushes", default: 0, null: false
    t.jsonb "rows_details", default: "[]", null: false
    t.decimal "row_spacing", precision: 5, scale: 2, default: "3.0"
    t.decimal "bush_spacing", precision: 5, scale: 2, default: "1.5"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["polygon"], name: "index_vineyards_on_polygon", using: :gist
    t.index ["rows_details"], name: "index_vineyards_on_rows_details", using: :gin
    t.index ["user_id", "name"], name: "index_vineyards_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_vineyards_on_user_id"
    t.check_constraint "area_hectares <= 20::numeric OR area_hectares IS NULL", name: "check_area_limit"
    t.check_constraint "bush_spacing >= 1.2 AND bush_spacing <= 1.8", name: "check_bush_spacing_range"
    t.check_constraint "row_spacing >= 2.0 AND row_spacing <= 3.0", name: "check_row_spacing_range"
    t.check_constraint "st_numpoints(st_exteriorring(polygon::geometry)) = 5 AND st_isclosed(st_exteriorring(polygon::geometry)) AND st_isvalid(polygon::geometry)", name: "check_polygon_is_rectangle"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "folders", "folders", column: "parent_id", on_delete: :cascade
  add_foreign_key "folders", "users", on_delete: :cascade
  add_foreign_key "media_items", "folders", on_delete: :cascade
  add_foreign_key "vineyards", "users", on_delete: :cascade
end
