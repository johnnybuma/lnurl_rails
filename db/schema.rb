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

ActiveRecord::Schema[7.0].define(version: 2026_08_06_150000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

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

  create_table "block_data", force: :cascade do |t|
    t.integer "block_number"
    t.string "block_hash"
    t.text "data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "block_histories", force: :cascade do |t|
    t.integer "block_number"
    t.string "block_hash"
    t.text "data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["block_number"], name: "index_block_histories_on_block_number"
  end

  create_table "chain_data", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "key"
    t.text "value"
  end

  create_table "messages", force: :cascade do |t|
    t.text "content"
    t.bigint "user_id", null: false
    t.bigint "room_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["room_id"], name: "index_messages_on_room_id"
    t.index ["user_id"], name: "index_messages_on_user_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_private"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "role"
    t.string "username"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "wallet_address_balance_snapshots", force: :cascade do |t|
    t.string "wallet_name", null: false
    t.string "address", null: false
    t.string "label"
    t.decimal "balance", precision: 24, scale: 8, default: "0.0", null: false
    t.integer "utxo_count", default: 0, null: false
    t.string "key_fingerprint"
    t.integer "key_line"
    t.integer "scan_height"
    t.string "bestblock"
    t.bigint "wallet_import_run_id"
    t.bigint "wallet_address_balance_id"
    t.datetime "scanned_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["scanned_at"], name: "idx_wabs_scanned_at"
    t.index ["wallet_address_balance_id"], name: "idx_wabs_balance_id"
    t.index ["wallet_import_run_id"], name: "idx_wabs_import_run"
    t.index ["wallet_name", "address", "scanned_at"], name: "idx_wabs_wallet_addr_scanned"
  end

  create_table "wallet_address_balances", force: :cascade do |t|
    t.string "wallet_name", null: false
    t.string "address", null: false
    t.string "label"
    t.decimal "balance", precision: 24, scale: 8, default: "0.0", null: false
    t.integer "utxo_count", default: 0, null: false
    t.integer "key_line"
    t.string "source_format"
    t.string "key_fingerprint"
    t.boolean "rescan_off_import", default: true, null: false
    t.integer "address_rank"
    t.integer "scan_height"
    t.string "bestblock"
    t.bigint "wallet_import_run_id"
    t.datetime "scanned_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "last_balance", precision: 24, scale: 8, default: "0.0", null: false
    t.integer "last_utxo_count", default: 0, null: false
    t.datetime "last_scanned_at"
    t.decimal "previous_balance", precision: 24, scale: 8, default: "0.0", null: false
    t.index ["key_fingerprint"], name: "index_wallet_address_balances_on_key_fingerprint"
    t.index ["label"], name: "index_wallet_address_balances_on_label"
    t.index ["scanned_at"], name: "index_wallet_address_balances_on_scanned_at"
    t.index ["wallet_import_run_id"], name: "index_wallet_address_balances_on_wallet_import_run_id"
    t.index ["wallet_name", "address"], name: "idx_wallet_addr_balances_unique", unique: true
  end

  create_table "wallet_extended_keys", force: :cascade do |t|
    t.string "wallet_name", null: false
    t.text "extended_key", null: false
    t.string "key_type"
    t.integer "receive_gap", default: 20, null: false
    t.integer "change_gap", default: 20, null: false
    t.integer "source_line"
    t.bigint "wallet_import_run_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["wallet_name", "extended_key"], name: "idx_wallet_xpub_unique", unique: true
    t.index ["wallet_name"], name: "index_wallet_extended_keys_on_wallet_name"
  end

  create_table "wallet_import_runs", force: :cascade do |t|
    t.string "wallet_name", null: false
    t.string "label_prefix"
    t.boolean "rescan", default: false, null: false
    t.boolean "auto_utxo_scan", default: true, null: false
    t.integer "keys_ok", default: 0, null: false
    t.integer "keys_failed", default: 0, null: false
    t.decimal "total_balance", precision: 24, scale: 8, default: "0.0", null: false
    t.integer "addresses_stored", default: 0, null: false
    t.string "status", default: "completed", null: false
    t.text "notes"
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_wallet_import_runs_on_created_at"
    t.index ["wallet_name"], name: "index_wallet_import_runs_on_wallet_name"
  end

  create_table "wallet_public_keys", force: :cascade do |t|
    t.string "wallet_name", null: false
    t.string "pubkey_hex"
    t.string "address"
    t.string "path"
    t.string "label"
    t.string "source_format"
    t.boolean "from_private_key", default: false, null: false
    t.integer "source_line"
    t.bigint "wallet_import_run_id"
    t.bigint "wallet_extended_key_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["path"], name: "index_wallet_public_keys_on_path"
    t.index ["wallet_name", "address"], name: "idx_wallet_pubkeys_wallet_addr"
    t.index ["wallet_name", "pubkey_hex"], name: "idx_wallet_pubkeys_wallet_pub"
    t.index ["wallet_name"], name: "index_wallet_public_keys_on_wallet_name"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "messages", "rooms"
  add_foreign_key "messages", "users"
  add_foreign_key "wallet_address_balance_snapshots", "wallet_address_balances"
  add_foreign_key "wallet_address_balance_snapshots", "wallet_import_runs"
  add_foreign_key "wallet_address_balances", "wallet_import_runs"
end
