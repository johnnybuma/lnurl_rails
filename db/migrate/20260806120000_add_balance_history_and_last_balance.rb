# frozen_string_literal: true

class AddBalanceHistoryAndLastBalance < ActiveRecord::Migration[7.0]
  def change
    add_column :wallet_address_balances, :last_balance, :decimal, precision: 24, scale: 8, default: 0, null: false
    add_column :wallet_address_balances, :last_utxo_count, :integer, default: 0, null: false
    add_column :wallet_address_balances, :last_scanned_at, :datetime
    add_column :wallet_address_balances, :previous_balance, :decimal, precision: 24, scale: 8, default: 0, null: false

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE wallet_address_balances
          SET last_balance = balance,
              last_utxo_count = utxo_count,
              last_scanned_at = scanned_at,
              previous_balance = 0
        SQL
      end
    end

    create_table :wallet_address_balance_snapshots do |t|
      t.string :wallet_name, null: false
      t.string :address, null: false
      t.string :label
      t.decimal :balance, precision: 24, scale: 8, null: false, default: 0
      t.integer :utxo_count, null: false, default: 0
      t.string :key_fingerprint
      t.integer :key_line
      t.integer :scan_height
      t.string :bestblock
      t.bigint :wallet_import_run_id
      t.bigint :wallet_address_balance_id
      t.datetime :scanned_at, null: false
      t.timestamps
    end

    add_index :wallet_address_balance_snapshots, :wallet_import_run_id, name: "idx_wabs_import_run"
    add_index :wallet_address_balance_snapshots, :wallet_address_balance_id, name: "idx_wabs_balance_id"
    add_index :wallet_address_balance_snapshots, %i[wallet_name address scanned_at],
              name: "idx_wabs_wallet_addr_scanned"
    add_index :wallet_address_balance_snapshots, :scanned_at, name: "idx_wabs_scanned_at"

    add_foreign_key :wallet_address_balance_snapshots, :wallet_import_runs, column: :wallet_import_run_id
    add_foreign_key :wallet_address_balance_snapshots, :wallet_address_balances, column: :wallet_address_balance_id
  end
end
