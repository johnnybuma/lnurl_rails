# frozen_string_literal: true

class WalletAddressBalance < ApplicationRecord
  belongs_to :wallet_import_run, optional: true
  has_many :wallet_address_balance_snapshots, dependent: :delete_all

  validates :wallet_name, presence: true
  validates :address, presence: true
  validates :balance, numericality: true

  scope :for_wallet, ->(name) { where(wallet_name: name) }
  scope :with_balance, -> { where("balance > 0 OR last_balance > 0") }
  scope :recent, -> { order(Arel.sql("COALESCE(last_scanned_at, scanned_at, updated_at) DESC")) }
  scope :by_address, -> { order(:address) }

  before_validation :sync_last_balance_defaults, on: :create

  # Upsert current scan and append immutable history snapshot.
  def self.record_scan!(attrs)
    wallet_name = attrs.fetch(:wallet_name)
    address = attrs.fetch(:address)
    new_balance = attrs.fetch(:balance).to_f
    new_utxos = attrs.fetch(:utxo_count, 0).to_i
    scanned_at = attrs[:scanned_at] || Time.current

    rec = find_or_initialize_by(wallet_name: wallet_name, address: address)
    previous = rec.persisted? ? rec.balance.to_f : 0.0

    rec.assign_attributes(
      label: attrs[:label],
      previous_balance: previous,
      balance: new_balance,
      utxo_count: new_utxos,
      # last_* = most recent observation (always updated, including zeros)
      last_balance: new_balance,
      last_utxo_count: new_utxos,
      last_scanned_at: scanned_at,
      key_line: attrs[:key_line],
      source_format: attrs[:source_format],
      key_fingerprint: attrs[:key_fingerprint],
      rescan_off_import: attrs.key?(:rescan_off_import) ? attrs[:rescan_off_import] : true,
      address_rank: attrs[:address_rank],
      scan_height: attrs[:scan_height],
      bestblock: attrs[:bestblock],
      wallet_import_run: attrs[:wallet_import_run],
      scanned_at: scanned_at
    )
    rec.save!

    snap = rec.wallet_address_balance_snapshots.create!(
      wallet_name: wallet_name,
      address: address,
      label: rec.label,
      balance: new_balance,
      utxo_count: new_utxos,
      key_fingerprint: rec.key_fingerprint,
      key_line: rec.key_line,
      scan_height: rec.scan_height,
      bestblock: rec.bestblock,
      wallet_import_run: attrs[:wallet_import_run],
      scanned_at: scanned_at
    )

    [rec, snap]
  end

  def self.total_for_wallet(name)
    for_wallet(name).sum(:last_balance)
  end

  def self.last_balances_map(wallet_name)
    for_wallet(wallet_name).pluck(:address, :last_balance, :last_scanned_at, :label, :utxo_count, :previous_balance).each_with_object({}) do |row, h|
      addr, last_bal, last_at, label, utxos, prev = row
      h[addr] = {
        last_balance: last_bal.to_f,
        last_scanned_at: last_at,
        label: label,
        last_utxo_count: utxos.to_i,
        previous_balance: prev.to_f
      }
    end
  end

  def display_last_balance
    (last_balance.presence || balance).to_f
  end

  private

  def sync_last_balance_defaults
    self.last_balance = balance if last_balance.nil? || (last_balance.to_f.zero? && balance.to_f.positive? && last_scanned_at.nil?)
    self.last_utxo_count ||= utxo_count
    self.last_scanned_at ||= scanned_at
    self.previous_balance ||= 0
  end
end
