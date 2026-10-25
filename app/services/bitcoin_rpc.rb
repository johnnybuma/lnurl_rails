# frozen_string_literal: true

require "httparty"
require "json"

# Thin JSON-RPC client for Bitcoin Core (node + optional wallet endpoint).
class BitcoinRpc
  include HTTParty
  format :json
  default_timeout 120

  class Error < StandardError
    attr_reader :code, :rpc_name

    def initialize(message, code: nil, rpc_name: nil)
      super(message)
      @code = code
      @rpc_name = rpc_name
    end
  end

  def self.from_env(wallet: nil)
    w = wallet
    w = ENV["BITCOIN_WALLET_NAME"] if w.nil? || w.to_s.strip.empty?
    w = nil if w.respond_to?(:to_s) && w.to_s.strip.empty?
    new(
      url: ENV.fetch("BITCOIN_RPC_URL"),
      username: ENV.fetch("BITCOIN_RPC_USERNAME"),
      password: ENV.fetch("BITCOIN_RPC_PASSWORD"),
      wallet: w
    )
  end

  def initialize(url:, username:, password:, wallet: nil)
    @base_url = url.to_s.sub(%r{/*$}, "")
    @username = username
    @password = password
    @wallet = wallet.to_s.strip.empty? ? nil : wallet.to_s.strip
  end

  def with_wallet(name)
    self.class.new(url: @base_url, username: @username, password: @password, wallet: name)
  end

  def wallet_name
    @wallet
  end

  # --- generic ---

  # timeout: seconds for this HTTP request (wallet rescans need much longer)
  def call(method, *params, timeout: nil)
    timeout ||= Integer(ENV.fetch("BITCOIN_RPC_TIMEOUT", "120"))

    response = self.class.post(
      endpoint,
      basic_auth: { username: @username, password: @password },
      headers: { "Content-Type" => "application/json" },
      timeout: timeout,
      open_timeout: [timeout, 30].min,
      read_timeout: timeout,
      body: {
        jsonrpc: "1.0",
        id: "nodeview",
        method: method,
        params: params
      }.to_json
    )

    body = parse_body(response)
    if body["error"]
      err = body["error"]
      raise Error.new(err["message"].presence || "RPC error", code: err["code"], rpc_name: method)
    end

    body["result"]
  rescue Error
    raise
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::EPIPE, EOFError => e
    raise Error.new(
      "#{method} timed out or connection dropped (#{e.class}: #{e.message}). " \
      "If a wallet is rescanning (getwalletinfo → scanning), wait or run: " \
      "bitcoin-cli -rpcwallet=NAME abortrescan — then retry with rescan unchecked.",
      rpc_name: method
    )
  rescue StandardError => e
    raise Error.new("#{method} failed: #{e.message}", rpc_name: method)
  end

  def call_raw(method, *params)
    call(method, *params)
  rescue Error => e
    { "error" => { "code" => e.code, "message" => e.message }, "method" => method }
  end

  # --- wallet lifecycle ---

  def list_wallets
    call("listwallets")
  end

  def list_wallet_dir
    call("listwalletdir")
  rescue Error
    { "wallets" => [] }
  end

  def load_wallet(name)
    call("loadwallet", name)
  end

  def unload_wallet(name = nil)
    name = (name.presence || @wallet).to_s.strip
    raise Error.new("Wallet name is required", rpc_name: "unloadwallet") if name.blank?

    # unloadwallet is a node-level RPC; pass name explicitly
    node = self.class.new(url: @base_url, username: @username, password: @password, wallet: nil)
    node.call("unloadwallet", name, timeout: 120)
  end

  def create_wallet(name, disable_private_keys: false, blank: false, passphrase: "", avoid_reuse: false, descriptors: false, load_on_startup: true)
    # Bitcoin Core 0.21+ signature varies; pass common args.
    call(
      "createwallet",
      name,
      disable_private_keys,
      blank,
      passphrase,
      avoid_reuse,
      descriptors,
      load_on_startup
    )
  end

  def ensure_wallet!(name)
    name = name.to_s.strip
    raise Error.new("Wallet name is required") if name.blank?

    wallets = begin
      list_wallets
    rescue Error => e
      raise Error.new(
        "Wallet RPC is unavailable (#{e.message}). " \
        "Enable the wallet in bitcoind (remove disablewallet=1 / rebuild with wallet support), then restart.",
        code: e.code,
        rpc_name: "listwallets"
      )
    end

    return with_wallet(name) if wallets.include?(name)

    begin
      load_wallet(name)
    rescue Error
      create_wallet(name, descriptors: false)
    end

    with_wallet(name)
  end

  def wallet_info
    call("getwalletinfo")
  end

  # --- keys / addresses ---

  def import_private_key(wif, label: "", rescan: true)
    # importprivkey "privkey" ( "label" ) ( rescan )
    # rescan=true can hold the RPC socket for a very long time; use a long timeout.
    # rescan=false is normally quick unless another wallet RPC is already blocking.
    timeout = rescan ? Integer(ENV.fetch("BITCOIN_RPC_IMPORT_RESCAN_TIMEOUT", "86400")) : Integer(ENV.fetch("BITCOIN_RPC_IMPORT_TIMEOUT", "300"))
    call("importprivkey", wif.to_s.strip, label.to_s, !!rescan, timeout: timeout)
  end

  # importpubkey "pubkey" ( "label" ) ( rescan ) — watch-only
  def import_public_key(pubkey_hex, label: "", rescan: false)
    timeout = rescan ? Integer(ENV.fetch("BITCOIN_RPC_IMPORT_RESCAN_TIMEOUT", "86400")) : Integer(ENV.fetch("BITCOIN_RPC_IMPORT_TIMEOUT", "300"))
    call("importpubkey", pubkey_hex.to_s.strip, label.to_s, !!rescan, timeout: timeout)
  end

  # importaddress "address" ( "label" ) ( rescan ) ( p2sh )
  def import_address(address, label: "", rescan: false, p2sh: false)
    timeout = rescan ? Integer(ENV.fetch("BITCOIN_RPC_IMPORT_RESCAN_TIMEOUT", "86400")) : Integer(ENV.fetch("BITCOIN_RPC_IMPORT_TIMEOUT", "300"))
    call("importaddress", address.to_s.strip, label.to_s, !!rescan, !!p2sh, timeout: timeout)
  end

  def abort_rescan
    call("abortrescan", timeout: 60)
  rescue Error
    false
  end

  def scanning?
    info = wallet_info
    scan = info["scanning"]
    scan != false && !scan.nil?
  rescue Error
    false
  end

  def list_address_groupings
    call("listaddressgroupings")
  rescue Error
    []
  end

  def list_received_by_address(minconf: 0, include_empty: true, include_watchonly: true)
    call("listreceivedbyaddress", minconf, include_empty, include_watchonly)
  rescue Error
    []
  end

  def list_labels
    call("listlabels")
  rescue Error
    []
  end

  def get_addresses_by_label(label)
    call("getaddressesbylabel", label)
  rescue Error
    {}
  end

  def list_unspent(minconf: 0, maxconf: 9999999)
    call("listunspent", minconf, maxconf)
  rescue Error
    []
  end

  def get_balances
    call("getbalances")
  rescue Error
    nil
  end

  def get_balance
    call("getbalance")
  rescue Error
    nil
  end

  def get_address_info(address)
    call("getaddressinfo", address.to_s.strip)
  rescue Error
    nil
  end

  # dumpprivkey "address" → WIF (wallet must hold the private key). Never log/persist return value.
  def dump_priv_key(address)
    call("dumpprivkey", address.to_s.strip, timeout: 60)
  end

  # Classify every known wallet address via getaddressinfo.
  # scope: :spendable (imported privkeys / ismine && !watchonly),
  #        :watchonly (iswatchonly),
  #        :all
  def addresses_by_scope(scope: :all)
    scope = scope.to_sym
    rows = all_addresses
    classified = []

    rows.each do |row|
      addr = row[:address]
      next if addr.blank?

      info = get_address_info(addr) || {}
      ismine = !!info["ismine"]
      iswatch = !!info["iswatchonly"]
      pubkey = info["pubkey"].presence

      kind =
        if iswatch || (!ismine && pubkey.present?)
          :watchonly
        elsif ismine
          :spendable
        else
          :other
        end

      next if scope == :spendable && kind != :spendable
      next if scope == :watchonly && kind != :watchonly
      next if scope != :all && kind == :other

      classified << row.merge(
        kind: kind,
        ismine: ismine,
        iswatchonly: iswatch,
        pubkey: pubkey,
        purpose: info["purpose"]
      )
    end

    classified
  end

  # Build scantxoutset descriptors for a scope of wallet keys.
  # For each address: addr(). When pubkey known, also pkh/wpkh/sh(wpkh) so
  # alternate script types for the same key are found without a wallet rescan.
  def scan_descriptors_for_scope(scope: :all)
    descs = []
    seen = {}
    addresses_by_scope(scope: scope).each do |row|
      addr = row[:address]
      if addr.present? && !seen[addr]
        descs << "addr(#{addr})"
        seen[addr] = true
      end
      pub = row[:pubkey].to_s
      next if pub.blank?

      %W[pkh(#{pub}) wpkh(#{pub}) sh(wpkh(#{pub}))].each do |d|
        next if seen[d]

        descs << d
        seen[d] = true
      end
    end
    descs
  end

  # Fast current balance from the UTXO set — does NOT require wallet rescan.
  # scanobjects: array of descriptor strings, e.g. "addr(bc1…)", "combo(WIF)"
  # Uses the node endpoint (not /wallet/…); timeout can be a few minutes on large UTXO sets.
  def scantxoutset(scanobjects, timeout: nil)
    timeout ||= Integer(ENV.fetch("BITCOIN_RPC_SCANTXOUTSET_TIMEOUT", "600"))
    objs = Array(scanobjects).map(&:to_s).reject(&:blank?).uniq
    raise Error.new("scantxoutset requires at least one address/descriptor", rpc_name: "scantxoutset") if objs.empty?

    # Run against base node URL (wallet path not required)
    node = self.class.new(url: @base_url, username: @username, password: @password, wallet: nil)

    # Chunk large descriptor sets (very large wallets)
    chunk_size = Integer(ENV.fetch("BITCOIN_RPC_SCANTXOUTSET_CHUNK", "250"))
    if objs.size <= chunk_size
      return node.call("scantxoutset", "start", objs, timeout: timeout)
    end

    merged = {
      "success" => true,
      "total_amount" => 0.0,
      "txouts" => 0,
      "height" => nil,
      "bestblock" => nil,
      "unspents" => []
    }
    objs.each_slice(chunk_size) do |chunk|
      part = node.call("scantxoutset", "start", chunk, timeout: timeout)
      next unless part.is_a?(Hash)

      merged["total_amount"] = merged["total_amount"].to_f + part["total_amount"].to_f
      merged["txouts"] = part["txouts"] if part["txouts"]
      merged["height"] = part["height"] if part["height"]
      merged["bestblock"] = part["bestblock"] if part["bestblock"]
      merged["unspents"].concat(Array(part["unspents"]))
      merged["success"] &&= part["success"] != false
    end
    # Deduplicate unspents by txid:vout
    seen_u = {}
    merged["unspents"] = merged["unspents"].select do |u|
      key = "#{u["txid"]}:#{u["vout"]}"
      next false if seen_u[key]

      seen_u[key] = true
      true
    end
    merged["total_amount"] = merged["unspents"].sum { |u| u["amount"].to_f }
    merged
  end

  def scantxoutset_addresses(addresses, timeout: nil)
    addrs = Array(addresses).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    scantxoutset(addrs.map { |a| "addr(#{a})" }, timeout: timeout)
  end

  # Derive standard scripts from a WIF and scan the UTXO set (no rescan).
  def scantxoutset_combo_wif(wif, timeout: nil)
    scantxoutset(["combo(#{wif.to_s.strip})"], timeout: timeout)
  end

  # Scan UTXO set for all imported private-key addresses (spendable / ismine).
  def scantxoutset_imported_keys(timeout: nil)
    descs = scan_descriptors_for_scope(scope: :spendable)
    raise Error.new("No imported private-key addresses found in this wallet", rpc_name: "scantxoutset") if descs.empty?

    scantxoutset(descs, timeout: timeout)
  end

  # Scan UTXO set for watch-only (importpubkey / importaddress / xpub) addresses.
  def scantxoutset_watch_only(timeout: nil)
    descs = scan_descriptors_for_scope(scope: :watchonly)
    raise Error.new("No watch-only addresses found in this wallet", rpc_name: "scantxoutset") if descs.empty?

    scantxoutset(descs, timeout: timeout)
  end

  # Collect a unified address list from several RPCs.
  def all_addresses
    rows = {}

    list_received_by_address.each do |entry|
      addr = entry["address"]
      next if addr.blank?

      rows[addr] = {
        address: addr,
        amount: entry["amount"],
        confirmations: entry["confirmations"],
        label: entry["label"].presence || entry["account"],
        txids: entry["txids"] || [],
        source: "listreceivedbyaddress"
      }
    end

    list_address_groupings.each do |group|
      Array(group).each do |item|
        addr = item[0]
        next if addr.blank?

        rows[addr] ||= {
          address: addr,
          amount: item[1],
          confirmations: nil,
          label: item[2],
          txids: [],
          source: "listaddressgroupings"
        }
        rows[addr][:amount] ||= item[1]
        rows[addr][:label] ||= item[2]
      end
    end

    list_labels.each do |label|
      get_addresses_by_label(label).each do |addr, meta|
        rows[addr] ||= {
          address: addr,
          amount: nil,
          confirmations: nil,
          label: label,
          txids: [],
          source: "getaddressesbylabel"
        }
        purpose = meta.is_a?(Hash) ? meta["purpose"] : nil
        rows[addr][:purpose] = purpose
        rows[addr][:label] ||= label
      end
    end

    list_unspent.each do |utxo|
      addr = utxo["address"]
      next if addr.blank?

      rows[addr] ||= {
        address: addr,
        amount: 0,
        confirmations: utxo["confirmations"],
        label: utxo["label"],
        txids: [],
        source: "listunspent"
      }
      rows[addr][:amount] = rows[addr][:amount].to_f + utxo["amount"].to_f
    end

    rows.values.sort_by { |r| r[:address].to_s }
  end

  def wallet_available?
    call("listwallets")
    true
  rescue Error
    false
  end

  private

  def endpoint
    if @wallet.present?
      "#{@base_url}/wallet/#{ERB::Util.url_encode(@wallet)}"
    else
      "#{@base_url}/"
    end
  end

  def parse_body(response)
    return { "error" => { "code" => response.code, "message" => "HTTP #{response.code}" } } if response.body.blank?

    JSON.parse(response.body)
  rescue JSON::ParserError
    { "error" => { "code" => response.code, "message" => "Non-JSON RPC response (HTTP #{response.code})" } }
  end
end
