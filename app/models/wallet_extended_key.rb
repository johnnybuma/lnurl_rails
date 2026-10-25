# frozen_string_literal: true

# Stores account-level xpub/ypub/zpub so we can re-expand full address gaps later.
class WalletExtendedKey < ApplicationRecord
  belongs_to :wallet_import_run, optional: true

  validates :wallet_name, :extended_key, presence: true

  scope :for_wallet, ->(name) { where(wallet_name: name) }

  def self.remember!(wallet_name:, extended_key:, receive_gap: 20, change_gap: 20, source_line: nil, import_run: nil)
    key = extended_key.to_s.strip.split(%r{[\s:/]}).first.to_s
    return nil if key.blank?

    type = key[0, 4]
    rec = find_or_initialize_by(wallet_name: wallet_name, extended_key: key)
    rec.assign_attributes(
      key_type: type,
      receive_gap: receive_gap,
      change_gap: change_gap,
      source_line: source_line,
      wallet_import_run: import_run
    )
    rec.save!
    rec
  end
end
