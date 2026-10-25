# frozen_string_literal: true

class CreateWalletPublicKeys < ActiveRecord::Migration[7.0]
  def change
    create_table :wallet_public_keys do |t|
      t.string :wallet_name, null: false
      t.string :pubkey_hex # compressed/uncompressed hex; nil for address-only
      t.string :address
      t.string :path # e.g. 0/5 or 1/12
      t.string :label
      t.string :source_format # zpub:0/5, compressed_hex, wif, address, …
      t.boolean :from_private_key, null: false, default: false
      t.integer :source_line
      t.bigint :wallet_import_run_id
      t.bigint :wallet_extended_key_id
      t.timestamps
    end
    add_index :wallet_public_keys, :wallet_name
    add_index :wallet_public_keys, %i[wallet_name address], name: "idx_wallet_pubkeys_wallet_addr"
    add_index :wallet_public_keys, %i[wallet_name pubkey_hex], name: "idx_wallet_pubkeys_wallet_pub"
    add_index :wallet_public_keys, :path
  end
end
