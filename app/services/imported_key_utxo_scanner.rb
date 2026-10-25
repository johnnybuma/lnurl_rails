# frozen_string_literal: true

require "digest"

# After importprivkey(rescan=false): scan UTXO set for that key and persist
# the first MAX_ADDRESSES addresses + balances to Postgres.
# Never stores private keys / WIF.
class ImportedKeyUtxoScanner
  MAX_ADDRESSES = 20

  Result = Struct.new(
    :key_fingerprint, :label, :total_balance, :utxo_count, :addresses_stored, :address_rows, :scan_height, :error,
    keyword_init: true
  )

  class << self
    # @param client [BitcoinRpc] node-capable client (scantxoutset)
    # @param wallet_rpc [BitcoinRpc] wallet-scoped client
    # @param wif [String]
    # @param label [String]
    # @param wallet_name [String]
    # @param key_line [Integer]
    # @param source_format [String]
    # @param import_run [WalletImportRun, nil]
    def scan_and_store!(
      client:,
      wallet_rpc:,
      wif:,
      label:,
      wallet_name:,
      key_line: nil,
      source_format: "wif",
      import_run: nil,
      rescan_off: true
    )
      fingerprint = key_fingerprint(wif)
      rows = []

      # 1) Full-script coverage for this key (best balance accuracy without rescan)
      combo_result = client.scantxoutset(["combo(#{wif})"])
      unspents = Array(combo_result.is_a?(Hash) ? combo_result["unspents"] : [])
      total = combo_result.is_a?(Hash) ? combo_result["total_amount"].to_f : 0.0
      height = combo_result.is_a?(Hash) ? combo_result["height"] : nil
      bestblock = combo_result.is_a?(Hash) ? combo_result["bestblock"] : nil

      # 2) Addresses known to the wallet for this label (+ any addr() in scan descs)
      address_list = collect_addresses(wallet_rpc, label: label, unspents: unspents)
      address_list = address_list.first(MAX_ADDRESSES)

      # 3) Per-address balances: prefer addr() scan on the capped list when we have addresses
      balances_by_addr = Hash.new(0.0)
      counts_by_addr = Hash.new(0)

      if address_list.any?
        addr_descs = address_list.map { |a| "addr(#{a})" }
        # Also keep script-type coverage from combo for amounts that only match non-addr descs
        addr_scan = client.scantxoutset(addr_descs)
        Array(addr_scan.is_a?(Hash) ? addr_scan["unspents"] : []).each do |u|
          addr = address_from_unspent(u) || match_address_from_list(u, address_list)
          next if addr.blank?

          balances_by_addr[addr] += u["amount"].to_f
          counts_by_addr[addr] += 1
        end
        # If addr scan found nothing but combo found funds, fall back to grouping combo unspents
        if balances_by_addr.values.sum.zero? && total.positive?
          group_unspents_into!(unspents, balances_by_addr, counts_by_addr, address_list)
        end
      else
        group_unspents_into!(unspents, balances_by_addr, counts_by_addr, [])
        # If still no addresses, store a synthetic placeholder only if total > 0
        if balances_by_addr.empty? && total.positive?
          synth = "combo:#{fingerprint}"
          balances_by_addr[synth] = total
          counts_by_addr[synth] = unspents.size
          address_list = [synth]
        end
      end

      scanned_at = Time.current

      # Ensure first 20 from address_list appear even at 0 balance (for tracking)
      address_list.first(MAX_ADDRESSES).each_with_index do |addr, rank|
        bal = balances_by_addr[addr].to_f
        cnt = counts_by_addr[addr].to_i
        rec, = WalletAddressBalance.record_scan!(
          wallet_name: wallet_name,
          address: addr,
          label: label,
          balance: bal,
          utxo_count: cnt,
          key_line: key_line,
          source_format: source_format,
          key_fingerprint: fingerprint,
          rescan_off_import: rescan_off,
          address_rank: rank + 1,
          scan_height: height,
          bestblock: bestblock,
          wallet_import_run: import_run,
          scanned_at: scanned_at
        )
        rows << rec
      end

      # Any extra addresses with balance from scan not in the first 20 list (up to cap)
      balances_by_addr.each do |addr, bal|
        next if address_list.include?(addr)
        next if rows.size >= MAX_ADDRESSES
        next if bal.to_f <= 0

        rec, = WalletAddressBalance.record_scan!(
          wallet_name: wallet_name,
          address: addr,
          label: label,
          balance: bal,
          utxo_count: counts_by_addr[addr].to_i,
          key_line: key_line,
          source_format: source_format,
          key_fingerprint: fingerprint,
          rescan_off_import: rescan_off,
          address_rank: rows.size + 1,
          scan_height: height,
          bestblock: bestblock,
          wallet_import_run: import_run,
          scanned_at: scanned_at
        )
        rows << rec
      end

      Result.new(
        key_fingerprint: fingerprint,
        label: label,
        total_balance: total,
        utxo_count: unspents.size,
        addresses_stored: rows.size,
        address_rows: rows,
        scan_height: height,
        error: nil
      )
    rescue BitcoinRpc::Error, ActiveRecord::RecordInvalid => e
      Result.new(
        key_fingerprint: fingerprint,
        label: label,
        total_balance: 0,
        utxo_count: 0,
        addresses_stored: 0,
        address_rows: [],
        scan_height: nil,
        error: e.message
      )
    end

    def key_fingerprint(wif)
      Digest::SHA256.hexdigest(wif.to_s)[0, 16]
    end

    private

    def collect_addresses(wallet_rpc, label:, unspents:)
      addrs = []
      begin
        labeled = wallet_rpc.get_addresses_by_label(label.to_s)
        addrs.concat(labeled.keys) if labeled.is_a?(Hash)
      rescue StandardError
        # ignore
      end

      unspents.each do |u|
        a = address_from_unspent(u)
        addrs << a if a.present?
      end

      # Also pull recently seen wallet addresses that share the label via all_addresses
      begin
        wallet_rpc.all_addresses.each do |row|
          next unless row[:label].to_s == label.to_s || row[:label].to_s.start_with?(label.to_s)

          addrs << row[:address] if row[:address].present?
        end
      rescue StandardError
        # ignore
      end

      addrs.map(&:to_s).reject(&:blank?).uniq
    end

    def address_from_unspent(u)
      desc = (u["desc"] || u[:desc]).to_s
      if (m = desc.match(/addr\(([^)]+)\)/))
        return m[1]
      end

      # Some Core versions include address field
      u["address"].presence || u[:address].presence
    end

    def match_address_from_list(u, address_list)
      spk = (u["scriptPubKey"] || u[:script_pub_key]).to_s
      return nil if spk.blank?

      # Weak match not available without full decoder; skip
      nil
    end

    def group_unspents_into!(unspents, balances_by_addr, counts_by_addr, address_list)
      unspents.each do |u|
        addr = address_from_unspent(u)
        if addr.blank? && address_list.size == 1
          addr = address_list.first
        end
        next if addr.blank?

        balances_by_addr[addr] += u["amount"].to_f
        counts_by_addr[addr] += 1
      end
    end
  end
end
