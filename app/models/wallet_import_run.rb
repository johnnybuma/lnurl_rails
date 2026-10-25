# frozen_string_literal: true

class WalletImportRun < ApplicationRecord
  has_many :wallet_address_balances, dependent: :nullify

  validates :wallet_name, presence: true

  scope :for_wallet, ->(name) { where(wallet_name: name) }
  scope :recent, -> { order(created_at: :desc) }
end
