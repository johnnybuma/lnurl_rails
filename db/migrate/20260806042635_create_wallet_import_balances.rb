# frozen_string_literal: true

class CreateWalletImportBalances < ActiveRecord::Migration[7.0]
  def change
    create_table :wallet_import_runs do |t|
      t.string :wallet_name, null: false
      t.string :label_prefix
      t.boolean :rescan, null: false, default: false
      t.boolean :auto_utxo_scan, null: false, default: true
      t.integer :keys_ok, null: false, default: 0
      t.integer :keys_failed, null: false, default: 0
      t.decimal :total_balance, precision: 24, scale: 8, null: false, default: 0
      t.integer :addresses_stored, null: false, default: 0
      t.string :status, null: false, default: "completed"
      t.text :notes
      t.bigint :user_id
      t.timestamps
    end
    add_index :wallet_import_runs, :wallet_name
    add_index :wallet_import_runs, :created_at

    create_table :wallet_address_balances do |t|
      t.string :wallet_name, null: false
      t.string :address, null: false
      t.string :label
      t.decimal :balance, precision: 24, scale: 8, null: false, default: 0
      t.integer :utxo_count, null: false, default: 0
      t.integer :key_line
      t.string :source_format
      t.string :key_fingerprint # short non-reversible id of key batch line (not WIF)
      t.boolean :rescan_off_import, null: false, default: true
      t.integer :address_rank # 1..20 per key
      t.integer :scan_height
      t.string :bestblock
      t.references :wallet_import_run, foreign_key: true, null: true
      t.datetime :scanned_at
      t.timestamps
    end
    add_index :wallet_address_balances, %i[wallet_name address], unique: true, name: "idx_wallet_addr_balances_unique"
    add_index :wallet_address_balances, :label
    add_index :wallet_address_balances, :key_fingerprint
    add_index :wallet_address_balances, :scanned_at
  end
end
