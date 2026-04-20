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
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.decimal "north_lat", precision: 10, scale: 7, null: false
    t.decimal "south_lat", precision: 10, scale: 7, null: false
    t.decimal "east_lng", precision: 10, scale: 7, null: false
    t.decimal "west_lng", precision: 10, scale: 7, null: false
    t.string "grape_variety"
    t.integer "planting_year"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "name"], name: "index_vineyards_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_vineyards_on_user_id"
    t.check_constraint "north_lat > south_lat AND east_lng > west_lng AND north_lat >= '-90'::integer::numeric AND north_lat <= 90::numeric AND south_lat >= '-90'::integer::numeric AND south_lat <= 90::numeric AND east_lng >= '-180'::integer::numeric AND east_lng <= 180::numeric AND west_lng >= '-180'::integer::numeric AND west_lng <= 180::numeric", name: "check_coordinates"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "folders", "folders", column: "parent_id", on_delete: :cascade
  add_foreign_key "folders", "users", on_delete: :cascade
  add_foreign_key "media_items", "folders", on_delete: :cascade
  add_foreign_key "vineyards", "users", on_delete: :cascade
end
