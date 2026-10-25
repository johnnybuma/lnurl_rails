# frozen_string_literal: true

# Every public key / address we import — so Load ALL / re-scan never depends on re-paste.
class WalletPublicKey < ApplicationRecord
  belongs_to :wallet_import_run, optional: true
  belongs_to :wallet_extended_key, optional: true

  scope :for_wallet, ->(name) { where(wallet_name: name) }

  def self.remember!(
    wallet_name:,
    pubkey_hex: nil,
    address: nil,
    path: nil,
    label: nil,
    source_format: nil,
    from_private_key: false,
    source_line: nil,
    import_run: nil,
    extended_key: nil
  )
    pub = pubkey_hex.to_s.downcase.presence
    addr = address.to_s.presence
    return nil if pub.blank? && addr.blank?

    rec =
      if addr.present?
        find_or_initialize_by(wallet_name: wallet_name, address: addr)
      else
        find_or_initialize_by(wallet_name: wallet_name, pubkey_hex: pub, address: nil)
      end

    rec.assign_attributes(
      pubkey_hex: pub || rec.pubkey_hex,
      address: addr || rec.address,
      path: path.presence || rec.path,
      label: label.presence || rec.label,
      source_format: source_format.presence || rec.source_format,
      from_private_key: from_private_key || rec.from_private_key,
      source_line: source_line || rec.source_line,
      wallet_import_run: import_run || rec.wallet_import_run,
      wallet_extended_key: extended_key || rec.wallet_extended_key
    )
    rec.save!
    rec
  end
end
