# frozen_string_literal: true

class WalletAddressBalanceSnapshot < ApplicationRecord
  belongs_to :wallet_import_run, optional: true
  belongs_to :wallet_address_balance, optional: true

  validates :wallet_name, :address, presence: true

  scope :for_wallet, ->(name) { where(wallet_name: name) }
  scope :for_address, ->(addr) { where(address: addr) }
  scope :newest_first, -> { order(scanned_at: :desc, id: :desc) }

  # Latest snapshot row per address for a wallet
  def self.latest_by_address(wallet_name)
    for_wallet(wallet_name)
      .select("DISTINCT ON (address) wallet_address_balance_snapshots.*")
      .order(Arel.sql("address ASC, scanned_at DESC, id DESC"))
  end
end
