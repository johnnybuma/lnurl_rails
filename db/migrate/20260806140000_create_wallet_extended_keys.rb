# frozen_string_literal: true

class CreateWalletExtendedKeys < ActiveRecord::Migration[7.0]
  def change
    create_table :wallet_extended_keys do |t|
      t.string :wallet_name, null: false
      t.text :extended_key, null: false # xpub/ypub/zpub/… (public only)
      t.string :key_type # zpub, xpub, …
      t.integer :receive_gap, null: false, default: 20
      t.integer :change_gap, null: false, default: 20
      t.integer :source_line
      t.bigint :wallet_import_run_id
      t.timestamps
    end
    add_index :wallet_extended_keys, :wallet_name
    add_index :wallet_extended_keys, %i[wallet_name extended_key], unique: true, name: "idx_wallet_xpub_unique"
  end
end
