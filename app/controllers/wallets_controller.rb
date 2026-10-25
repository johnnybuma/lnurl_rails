# frozen_string_literal: true

class WalletsController < ApplicationController
  # Auto-generated wallet / label pattern: nodeviewWallet01, nodeviewWallet02, …
  AUTO_WALLET_PREFIX = "nodeviewWallet"

  before_action :require_admin!
  before_action :set_wallet_name, except: %i[index create batch_import rescan_all_utxos refill_all_private_keys]
  before_action :set_defaults, only: %i[show index]

  # GET /wallets — list every known wallet (loaded + on-disk)
  def index
    load_wallet_catalog!
    @network = detect_network(node_client)
    @next_auto_wallet_name = next_auto_wallet_name(node_client)
  rescue BitcoinRpc::Error => e
    @wallet_rpc_available = false
    @wallet_summaries = []
    @loaded_wallets = []
    @wallet_dir_names = []
    @next_auto_wallet_name = "#{AUTO_WALLET_PREFIX}01"
    flash.now[:alert] = humanize_rpc_error(e)
  end

  # POST /wallets — create (and load) a new legacy wallet (optional manual create)
  def create
    name = params[:name].to_s.strip
    name = next_auto_wallet_name(node_client) if name.blank?

    if name.match?(%r{[/\s]})
      return respond_index_alert!("Invalid wallet name (no spaces or slashes).")
    end

    descriptors = cast_bool(params[:descriptors], default: false)
    disable_private_keys = cast_bool(params[:disable_private_keys], default: false)
    client = node_client
    client.create_wallet(
      name,
      disable_private_keys: disable_private_keys,
      blank: cast_bool(params[:blank], default: false),
      descriptors: descriptors,
      load_on_startup: true
    )
    respond_to do |format|
      format.turbo_stream { redirect_to wallet_path(name), notice: "Wallet “#{name}” created and loaded.", status: :see_other }
      format.html { redirect_to wallet_path(name), notice: "Wallet “#{name}” created and loaded." }
    end
  rescue BitcoinRpc::Error => e
    respond_index_alert!(humanize_rpc_error(e))
  end

  # POST /wallets/batch_import
  # INDEX ONLY — Turbo Stream: returns immediately, work runs in background, live log streams.
  def batch_import
    raw = params[:material].presence || params[:private_keys].presence || params[:private_key].to_s
    if raw.to_s.strip.blank?
      return respond_index_alert!("Paste private keys, pubkeys, xpubs, and/or addresses.")
    end

    material = raw.to_s.dup
    compressed = cast_bool(params[:compressed], default: true)
    auto_utxo = cast_bool(params[:auto_utxo_scan], default: true)
    user_id = current_user.id

    reset_index_log!(user_id: user_id, message: "Batch import queued…")
    index_log("Batch import queued (Turbo) — work runs in background.", kind: :info, user_id: user_id)
    broadcast_job_status!(user_id: user_id, status: "running", message: "Batch import running…")

    spawn_async(label: "batch_import") do
      perform_batch_import!(
        material: material,
        user_id: user_id,
        compressed: compressed,
        auto_utxo: auto_utxo
      )
    end

    respond_index_started!("Batch import started — watch the live log (rescan OFF).")
  ensure
    params[:material] = "[FILTERED]" if params.key?(:material)
    params[:private_keys] = "[FILTERED]" if params.key?(:private_keys)
    params[:private_key] = "[FILTERED]" if params.key?(:private_key)
  end

  # POST /wallets/rescan_all_utxos — Turbo: immediate response + background scantxoutset
  def rescan_all_utxos
    client = node_client
    names = collect_known_wallet_names(client).sort
    if names.empty?
      return respond_index_alert!("No wallets found. Batch-import keys first.")
    end

    user_id = current_user.id
    reset_index_log!(user_id: user_id, message: "UTXO-only rescan of all wallets queued…")
    index_log(
      "UTXO-ONLY rescan queued for #{names.size} wallet(s). No chain rescan · no import.",
      kind: :info,
      user_id: user_id
    )
    broadcast_job_status!(user_id: user_id, status: "running", message: "Rescan ALL UTXO running…")

    spawn_async(label: "rescan_all_utxos") do
      perform_rescan_all_utxos!(names: names, user_id: user_id)
    end

    respond_index_started!("UTXO-only rescan started for #{names.size} wallet(s) — watch the live log.")
  rescue BitcoinRpc::Error => e
    respond_index_alert!(humanize_rpc_error(e))
  end

  # GET /wallets/:id
  def show
    load_wallet_state
    load_stored_balances!
    @extended_keys = WalletExtendedKey.for_wallet(@wallet_name).order(:id)
    @stored_public_keys = WalletPublicKey.for_wallet(@wallet_name).order(:path, :address).limit(500)
    @stored_public_keys_count = WalletPublicKey.for_wallet(@wallet_name).count
    @receive_gap = PublicKeyNormalizer::DEFAULT_RECEIVE
    @change_gap = PublicKeyNormalizer::DEFAULT_CHANGE
  rescue StandardError
    @extended_keys = []
    @stored_public_keys = []
    @stored_public_keys_count = 0
  end

  def import_key
    import_keys
  end

  def import_keys
    raw_blob = params[:private_keys].presence || params[:private_key].to_s
    # Label is never user-entered on batch form: wallet name (nodeviewWalletNN) or override
    label_prefix = params[:label].to_s.strip
    label_prefix = @wallet_name.to_s if label_prefix.blank?
    label_prefix = next_auto_wallet_name(node_client) if label_prefix.blank?
    # DEFAULT: rescan off (the proven bulk path)
    rescan = cast_bool(params[:rescan], default: false)
    compressed = cast_bool(params[:compressed], default: true)
    # DEFAULT: auto UTXO scan first 20 addresses per key → Postgres
    auto_utxo = cast_bool(params[:auto_utxo_scan], default: true)
    @compressed = compressed
    @rescan = rescan
    @auto_utxo_scan = auto_utxo
    @label_prefix = label_prefix

    if raw_blob.to_s.strip.blank?
      if @wallet_name.present? && action_name != "batch_import"
        redirect_to wallet_path(@wallet_name), alert: "Paste at least one private key."
      else
        redirect_to wallets_path, alert: "Paste at least one private key."
      end
      return
    end

    client = node_client
    network = detect_network(client)
    parsed = PrivateKeyConverter.parse_many(raw_blob, network: network, compressed: compressed)

    if parsed[:results].empty?
      load_wallet_state_safe
      flash.now[:alert] = "No valid private keys found. #{format_line_errors(parsed[:errors])}"
      return render_wallet_response(status: :unprocessable_entity)
    end

    wallet_rpc = client.ensure_wallet!(@wallet_name)
    if wallet_rpc.scanning?
      raise BitcoinRpc::Error.new(
        "Wallet “#{@wallet_name}” is already rescanning. Wait or abortrescan.",
        rpc_name: "importprivkey"
      )
    end

    import_run = WalletImportRun.create!(
      wallet_name: @wallet_name,
      label_prefix: label_prefix,
      rescan: rescan,
      auto_utxo_scan: auto_utxo,
      status: "running",
      user_id: current_user.id
    )
    @import_run = import_run

    clear_import_log!
    broadcast_log(
      "DEFAULT PATH: importprivkey rescan=#{rescan} · auto_utxo_scan=#{auto_utxo} " \
      "(first #{ImportedKeyUtxoScanner::MAX_ADDRESSES} addrs/key → Postgres) · " \
      "#{parsed[:results].size} key(s)…",
      kind: :info
    )

    ok = 0
    fail_n = 0
    scan_ok = 0
    scan_fail = 0
    total_scanned_balance = 0.0
    addresses_stored = 0

    parsed[:errors].each do |err|
      fail_n += 1
      broadcast_log("Line #{err.line} skipped (#{err.input_preview}): #{err.message}", kind: :error)
    end

    parsed[:results].each_with_index do |result, idx|
      is_last = idx == parsed[:results].size - 1
      # Only last key may rescan when user explicitly checked rescan
      key_rescan = rescan && is_last
      label = label_for(label_prefix, result.line, idx, parsed[:results].size)
      begin
        wallet_rpc.import_private_key(result.wif, label: label, rescan: key_rescan)
        ok += 1
        broadcast_log(
          "OK import L#{result.line}: #{result.source_format} → importprivkey " \
          "rescan=#{key_rescan} label=#{label.inspect}",
          kind: :ok
        )

        if auto_utxo
          broadcast_log(
            "UTXO scan L#{result.line}: combo(WIF) + first #{ImportedKeyUtxoScanner::MAX_ADDRESSES} addresses…",
            kind: :info
          )
          scan_result = ImportedKeyUtxoScanner.scan_and_store!(
            client: client,
            wallet_rpc: wallet_rpc,
            wif: result.wif,
            label: label,
            wallet_name: @wallet_name,
            key_line: result.line,
            source_format: result.source_format,
            import_run: import_run,
            rescan_off: !key_rescan
          )
          if scan_result.error
            scan_fail += 1
            broadcast_log("UTXO scan FAIL L#{result.line}: #{scan_result.error}", kind: :error)
          else
            scan_ok += 1
            total_scanned_balance += scan_result.total_balance.to_f
            addresses_stored += scan_result.addresses_stored.to_i
            broadcast_log(
              "UTXO scan OK L#{result.line}: #{scan_result.total_balance} BTC · " \
              "#{scan_result.utxo_count} UTXOs · #{scan_result.addresses_stored} addrs saved " \
              "(fp=#{scan_result.key_fingerprint})",
              kind: :ok
            )
          end
        end
      rescue BitcoinRpc::Error => e
        fail_n += 1
        broadcast_log("FAIL import L#{result.line}: #{e.message}", kind: :error)
      end
    end

    import_run.update!(
      keys_ok: ok,
      keys_failed: fail_n,
      total_balance: total_scanned_balance,
      addresses_stored: addresses_stored,
      status: "completed",
      notes: "auto_utxo=#{auto_utxo} scan_ok=#{scan_ok} scan_fail=#{scan_fail}"
    )

    load_wallet_state(wallet_rpc)
    load_stored_balances!
    @utxo_scan = {
      success: true,
      total_amount: total_scanned_balance,
      unspents: [],
      height: nil,
      scope: "auto post-import (#{ImportedKeyUtxoScanner::MAX_ADDRESSES}/key)",
      txouts: nil
    } if auto_utxo
    broadcast_replace_wallet_panels!

    notice_msg =
      "Wallet #{@wallet_name} · label #{label_prefix} · import #{ok} ok / #{fail_n} failed · " \
      "rescan=#{rescan ? "last-key-only" : "OFF"}" \
      "#{auto_utxo ? " · UTXO #{scan_ok} keys, #{addresses_stored} addrs stored, total=#{total_scanned_balance} BTC" : ""}."

    # Batch import from index: always land on the new wallet page
    if action_name == "batch_import" || params[:batch].present?
      redirect_to wallet_path(@wallet_name), notice: notice_msg
    else
      flash.now[:notice] = notice_msg
      render_wallet_response
    end
  rescue BitcoinRpc::Error => e
    @import_error = humanize_rpc_error(e)
    load_wallet_state_safe
    if action_name == "batch_import" || params[:batch].present?
      redirect_to wallets_path, alert: @import_error
    else
      flash.now[:alert] = @import_error
      broadcast_log("Import aborted: #{@import_error}", kind: :error)
      render_wallet_response(status: :unprocessable_entity)
    end
  ensure
    params[:private_key] = "[FILTERED]" if params[:private_key].present?
    params[:private_keys] = "[FILTERED]" if params[:private_keys].present?
  end

  def import_pubkeys
    raw_blob = params[:public_keys].to_s
    label_prefix = params[:label].to_s.strip
    rescan = cast_bool(params[:rescan], default: false)
    receive_count = params[:derive_receive].presence&.to_i || PublicKeyNormalizer::DEFAULT_RECEIVE
    change_count = params[:derive_change].presence&.to_i || PublicKeyNormalizer::DEFAULT_CHANGE
    @rescan = rescan
    @compressed = true
    @derive_receive = receive_count
    @derive_change = change_count

    if raw_blob.strip.blank?
      redirect_to wallet_path(@wallet_name), alert: "Paste hex pubkeys, xpub/ypub/zpub, or addresses."
      return
    end

    parsed = PublicKeyNormalizer.parse_many(
      raw_blob,
      receive_count: receive_count,
      change_count: change_count
    )
    if parsed[:results].empty?
      load_wallet_state_safe
      flash.now[:alert] = "No valid public keys/addresses found. #{format_line_errors(parsed[:errors])}"
      return render_wallet_response(status: :unprocessable_entity)
    end

    client = node_client
    wallet_rpc = client.ensure_wallet!(@wallet_name)
    if wallet_rpc.scanning?
      raise BitcoinRpc::Error.new(
        "Wallet “#{@wallet_name}” is rescanning — abortrescan first.",
        rpc_name: "importpubkey"
      )
    end

    clear_import_log!
    broadcast_log(
      "Starting watch-only import (#{parsed[:results].size} item(s); " \
      "xpub gap receive=#{receive_count} change=#{change_count}; rescan=#{rescan})…",
      kind: :info
    )

    ok = 0
    fail_n = 0
    parsed[:errors].each do |err|
      fail_n += 1
      broadcast_log("Line #{err.line} skipped (#{err.input_preview}): #{err.message}", kind: :error)
    end

    total = parsed[:results].size
    parsed[:results].each_with_index do |result, idx|
      is_last = idx == total - 1
      key_rescan = rescan && is_last
      label = label_for_pubkey(label_prefix, result, idx, total)
      begin
        import_watch_item!(wallet_rpc, result, label: label, rescan: key_rescan)
        ok += 1
        if total <= 30 || is_last || (idx % 10).zero? || idx < 3
          detail = [result.source_format, result.path, result.address.presence || result.hex&.first(16)].compact.join(" ")
          broadcast_log(
            "OK [#{idx + 1}/#{total}] L#{result.line}: #{detail}" \
            "#{key_rescan ? " (rescan ON)" : ""}",
            kind: :ok
          )
        end
      rescue BitcoinRpc::Error => e
        fail_n += 1
        broadcast_log("FAIL L#{result.line} #{result.path || result.source_format}: #{e.message}", kind: :error)
      end
    end

    load_wallet_state(wallet_rpc)
    broadcast_replace_wallet_panels!
    flash.now[:notice] =
      "Watch-only import finished: #{ok} ok, #{fail_n} failed (#{total} item(s))."
    render_wallet_response
  rescue BitcoinRpc::Error => e
    @import_error = humanize_rpc_error(e)
    load_wallet_state_safe
    flash.now[:alert] = @import_error
    render_wallet_response(status: :unprocessable_entity)
  end

  def load
    client = node_client
    wallet_rpc = client.ensure_wallet!(@wallet_name)
    load_wallet_state(wallet_rpc)
    load_stored_balances!
    broadcast_replace_wallet_panels!
    notice = "Wallet “#{@wallet_name}” loaded."
    # From index table: redirect to show. From show: turbo-stream panel replace.
    on_show = request.referer.to_s.include?("/wallets/#{ERB::Util.url_encode(@wallet_name)}") ||
              request.referer.to_s.end_with?("/wallets/#{@wallet_name}")
    if on_show
      flash.now[:notice] = notice
      render_wallet_response
    else
      respond_to do |format|
        format.turbo_stream { redirect_to wallet_path(@wallet_name), notice: notice, status: :see_other }
        format.html { redirect_to wallet_path(@wallet_name), notice: notice }
      end
    end
  rescue BitcoinRpc::Error => e
    @import_error = humanize_rpc_error(e)
    respond_to do |format|
      format.turbo_stream { redirect_to wallets_path, alert: @import_error, status: :see_other }
      format.html { redirect_to wallets_path, alert: @import_error }
    end
  end

  def unload
    node_client.unload_wallet(@wallet_name)
    notice = "Wallet “#{@wallet_name}” unloaded."
    respond_to do |format|
      format.turbo_stream { redirect_to wallets_path, notice: notice, status: :see_other }
      format.html { redirect_to wallets_path, notice: notice }
    end
  rescue BitcoinRpc::Error => e
    respond_to do |format|
      format.turbo_stream { redirect_to wallet_path(@wallet_name), alert: humanize_rpc_error(e), status: :see_other }
      format.html { redirect_to wallet_path(@wallet_name), alert: humanize_rpc_error(e) }
    end
  end

  def refresh
    load_wallet_state
    load_stored_balances!
    broadcast_replace_wallet_panels!
    flash.now[:notice] = "Wallet “#{@wallet_name}” refreshed."
    render_wallet_response
  rescue BitcoinRpc::Error => e
    @import_error = humanize_rpc_error(e)
    load_wallet_state_safe
    flash.now[:alert] = @import_error
    render_wallet_response(status: :unprocessable_entity)
  end

  def abort_rescan
    wallet_rpc = node_client.with_wallet(@wallet_name)
    wallet_rpc.abort_rescan
    load_wallet_state(wallet_rpc)
    broadcast_replace_wallet_panels!
    flash.now[:notice] = "abortrescan requested for “#{@wallet_name}”."
    render_wallet_response
  rescue BitcoinRpc::Error => e
    redirect_to wallet_path(@wallet_name), alert: humanize_rpc_error(e)
  end

  # Scan UTXO set for addresses already known to this wallet (no key paste / no import).
  # Turbo: returns immediately; progress + panels update via ActionCable.
  def scan_utxos
    @rescan = false
    client = node_client
    wallet_rpc = client.ensure_wallet!(@wallet_name)
    load_wallet_state(wallet_rpc)

    addrs = Array(@addresses).map { |r| r[:address] }.compact.uniq
    begin
      addrs |= WalletAddressBalance.for_wallet(@wallet_name).pluck(:address)
      addrs |= WalletPublicKey.for_wallet(@wallet_name).where.not(address: [nil, ""]).pluck(:address)
    rescue StandardError
      # ignore
    end
    addrs = addrs.map(&:to_s).reject { |a| a.start_with?("combo:") }.uniq

    if addrs.empty?
      flash.now[:alert] = "No addresses in this wallet yet. Use Batch import on /wallets first."
      return render_wallet_response(status: :unprocessable_entity)
    end

    wallet_name = @wallet_name
    user_id = current_user.id
    scan_objects = addrs.map { |a| "addr(#{a})" }
    clear_import_log!
    broadcast_log("UTXO scan queued (#{addrs.size} addresses) — Turbo returns now…", kind: :info)

    spawn_async(label: "scan_utxos") do
      @wallet_name = wallet_name
      @async_user_id = user_id
      c = node_client
      wr = c.with_wallet(wallet_name)
      run_utxo_scan_core!(c, scan_objects, scope_label: "all wallet addresses", wallet_rpc: wr)
    end

    flash.now[:notice] = "UTXO scan started for #{addrs.size} addresses — watch the live log."
    render_wallet_response
  rescue BitcoinRpc::Error => e
    @import_error = humanize_rpc_error(e)
    load_wallet_state_safe
    flash.now[:alert] = @import_error
    render_wallet_response(status: :unprocessable_entity)
  end

  def scan_imported_keys
    @rescan = false
    client = node_client
    wallet_rpc = client.ensure_wallet!(@wallet_name)
    load_wallet_state(wallet_rpc)

    clear_import_log!
    broadcast_log("Classifying spendable (imported private key) addresses…", kind: :info)
    descs = wallet_rpc.scan_descriptors_for_scope(scope: :spendable)
    if descs.empty?
      flash.now[:alert] = "No imported private-key addresses found. Import keys first."
      broadcast_log("No spendable addresses to scan.", kind: :error)
      return render_wallet_response(status: :unprocessable_entity)
    end

    wallet_name = @wallet_name
    user_id = current_user.id
    broadcast_log("Found #{descs.size} descriptor(s) — scan queued (Turbo)…", kind: :info)

    spawn_async(label: "scan_imported_keys") do
      @wallet_name = wallet_name
      @async_user_id = user_id
      c = node_client
      wr = c.with_wallet(wallet_name)
      run_utxo_scan_core!(c, descs, scope_label: "imported private keys", wallet_rpc: wr)
    end

    flash.now[:notice] = "Scan imported keys started — watch the live log."
    render_wallet_response
  rescue BitcoinRpc::Error => e
    @import_error = humanize_rpc_error(e)
    load_wallet_state_safe
    flash.now[:alert] = @import_error
    broadcast_log("Scan failed: #{@import_error}", kind: :error)
    render_wallet_response(status: :unprocessable_entity)
  end

  def scan_watch_only
    @rescan = false
    client = node_client
    wallet_rpc = client.ensure_wallet!(@wallet_name)
    load_wallet_state(wallet_rpc)

    clear_import_log!
    broadcast_log("Classifying watch-only addresses…", kind: :info)
    descs = wallet_rpc.scan_descriptors_for_scope(scope: :watchonly)
    if descs.empty?
      flash.now[:alert] = "No watch-only addresses found. Import pubkeys/xpubs/addresses first."
      broadcast_log("No watch-only addresses to scan.", kind: :error)
      return render_wallet_response(status: :unprocessable_entity)
    end

    wallet_name = @wallet_name
    user_id = current_user.id
    broadcast_log("Found #{descs.size} descriptor(s) — scan queued (Turbo)…", kind: :info)

    spawn_async(label: "scan_watch_only") do
      @wallet_name = wallet_name
      @async_user_id = user_id
      c = node_client
      wr = c.with_wallet(wallet_name)
      run_utxo_scan_core!(c, descs, scope_label: "watch-only", wallet_rpc: wr)
    end

    flash.now[:notice] = "Watch-only UTXO scan started — watch the live log."
    render_wallet_response
  rescue BitcoinRpc::Error => e
    @import_error = humanize_rpc_error(e)
    load_wallet_state_safe
    flash.now[:alert] = @import_error
    broadcast_log("Scan failed: #{@import_error}", kind: :error)
    render_wallet_response(status: :unprocessable_entity)
  end

  # POST /wallets/:id/refill_private_keys — Turbo immediate + background
  def refill_private_keys
    wallet_name = @wallet_name
    user_id = current_user.id
    clear_import_log!
    broadcast_log("Refill private keys queued (Turbo)…", kind: :info)

    spawn_async(label: "refill_private_keys") do
      @wallet_name = wallet_name
      @async_user_id = user_id
      client = node_client
      network = detect_network(client)
      wallet_rpc = client.ensure_wallet!(wallet_name)
      broadcast_log("Refill private keys: dumpprivkey → generate pubkeys → scripts…", kind: :info)
      result = refill_private_keys_for_wallet!(
        client: client,
        wallet_rpc: wallet_rpc,
        wallet_name: wallet_name,
        network: network,
        log: ->(msg, kind = :info) { broadcast_log(msg, kind: kind) }
      )
      load_wallet_state(wallet_rpc)
      load_stored_balances!
      broadcast_replace_wallet_panels!
      broadcast_log(result[:notice] || result[:alert] || "Refill done", kind: result[:alert] ? :error : :ok)
    end

    flash.now[:notice] = "Refill private keys started — watch the live log."
    load_wallet_state_safe
    load_stored_balances!
    render_wallet_response
  rescue BitcoinRpc::Error => e
    @import_error = humanize_rpc_error(e)
    load_wallet_state_safe
    flash.now[:alert] = @import_error
    render_wallet_response(status: :unprocessable_entity)
  end

  # POST /wallets/refill_all_private_keys — Turbo immediate + background
  def refill_all_private_keys
    wallets = WalletPublicKey.where(from_private_key: true).distinct.pluck(:wallet_name)
    # Also include wallets that have spendable keys even if no pubkeys stored yet
    begin
      wallets |= collect_known_wallet_names(node_client)
    rescue StandardError
      # ignore
    end
    wallets = wallets.map(&:to_s).reject(&:blank?).uniq.sort
    if wallets.empty?
      return respond_index_alert!("No wallets found to refill.")
    end

    user_id = current_user.id
    reset_index_log!(user_id: user_id, message: "Refill private keys queued…")
    index_log("Refill private keys queued for #{wallets.size} wallet(s)…", kind: :info, user_id: user_id)
    broadcast_job_status!(user_id: user_id, status: "running", message: "Refill ALL running…")

    spawn_async(label: "refill_all_private_keys") do
      perform_refill_all_private_keys!(wallet_names: wallets, user_id: user_id)
    end

    respond_index_started!("Refill private keys started for #{wallets.size} wallet(s) — watch the live log.")
  end

  # POST /wallets/:id/load_all_addresses
  # Re-derive full HD gap (default 20 receive + 20 change) for every stored xpub/zpub
  # (and optional re-paste), import missing addresses, UTXO-scan + Postgres.
  def load_all_addresses
    receive_n = (params[:receive_gap].presence || PublicKeyNormalizer::DEFAULT_RECEIVE).to_i.clamp(1, 200)
    change_n = (params[:change_gap].presence || PublicKeyNormalizer::DEFAULT_CHANGE).to_i.clamp(1, 200)
    auto_utxo = cast_bool(params[:auto_utxo_scan], default: true)
    extended_keys_raw = params[:extended_keys].to_s.dup
    wallet_name = @wallet_name
    user_id = current_user.id

    client = node_client
    wallet_rpc = client.ensure_wallet!(wallet_name)

    # Optional: paste xpubs again if not stored from an older import (sync so validation sees them)
    if extended_keys_raw.strip.present?
      extended_keys_raw.each_line.with_index(1) do |line, i|
        raw = line.strip
        next if raw.empty? || raw.start_with?("#", "//")
        next unless ExtendedPublicKey.xpub_like?(raw.split(%r{[\s:/]}).first.to_s) ||
                    ExtendedPublicKey::PREFIXES.any? { |p| raw.start_with?(p) }

        WalletExtendedKey.remember!(
          wallet_name: wallet_name,
          extended_key: raw,
          receive_gap: receive_n,
          change_gap: change_n,
          source_line: i
        )
      end
    end

    xpubs = WalletExtendedKey.for_wallet(wallet_name).to_a
    stored_pubs = WalletPublicKey.for_wallet(wallet_name).to_a
    clear_import_log!

    if xpubs.empty? && stored_pubs.empty?
      flash.now[:alert] =
        "No stored pubkeys/xpubs for this wallet. Paste xpub/zpub below (or re-batch-import so keys are stored)."
      broadcast_log("No pubkeys or extended keys on file.", kind: :error)
      load_wallet_state(wallet_rpc)
      load_stored_balances!
      @extended_keys = []
      @stored_public_keys_count = 0
      return render_wallet_response(status: :unprocessable_entity)
    end

    broadcast_log(
      "Load ALL addresses queued (Turbo) · gap receive=#{receive_n} change=#{change_n} · " \
      "#{xpubs.size} xpub(s) · #{stored_pubs.size} stored pubkey/address row(s)",
      kind: :info
    )

    spawn_async(label: "load_all_addresses") do
      perform_load_all_addresses!(
        wallet_name: wallet_name,
        user_id: user_id,
        receive_n: receive_n,
        change_n: change_n,
        auto_utxo: auto_utxo
      )
    end

    flash.now[:notice] = "Load ALL addresses started — watch the live log."
    load_wallet_state(wallet_rpc)
    load_stored_balances!
    @extended_keys = WalletExtendedKey.for_wallet(wallet_name)
    @stored_public_keys_count = WalletPublicKey.for_wallet(wallet_name).count
    render_wallet_response
  rescue BitcoinRpc::Error => e
    @import_error = humanize_rpc_error(e)
    load_wallet_state_safe
    flash.now[:alert] = @import_error
    render_wallet_response(status: :unprocessable_entity)
  end

  private

  def require_admin!
    return if current_user&.admin?

    redirect_to root_path, alert: "Admin access required for wallet operations."
  end

  def set_wallet_name
    @wallet_name = (params[:id].presence || params[:wallet].presence).to_s.strip
    if @wallet_name.blank?
      redirect_to wallets_path, alert: "Wallet name required."
    end
  end

  def set_defaults
    @rescan = false
    @compressed = true
    @auto_utxo_scan = true
  end

  def node_client
    BitcoinRpc.new(
      url: ENV.fetch("BITCOIN_RPC_URL"),
      username: ENV.fetch("BITCOIN_RPC_USERNAME"),
      password: ENV.fetch("BITCOIN_RPC_PASSWORD"),
      wallet: nil
    )
  end

  # Next free name: nodeviewWallet01, nodeviewWallet02, …
  def next_auto_wallet_name(client = nil)
    names = collect_known_wallet_names(client)
    max = 0
    names.each do |n|
      if (m = n.to_s.match(/\A#{Regexp.escape(AUTO_WALLET_PREFIX)}(\d+)\z/i))
        max = [max, m[1].to_i].max
      end
    end
    format("#{AUTO_WALLET_PREFIX}%02d", max + 1)
  end

  def collect_known_wallet_names(client = nil)
    names = []
    begin
      c = client || node_client
      names.concat(Array(c.list_wallets))
      dir = c.list_wallet_dir
      Array(dir["wallets"]).each do |w|
        names << (w.is_a?(Hash) ? w["name"] : w.to_s)
      end
    rescue BitcoinRpc::Error
      # ignore RPC failures — fall back to DB + in-memory
    end
    begin
      names.concat(WalletImportRun.distinct.pluck(:wallet_name))
      names.concat(WalletAddressBalance.distinct.pluck(:wallet_name))
    rescue StandardError
      # tables may not exist in some envs
    end
    names.map(&:to_s).reject(&:blank?).uniq
  end

  def redirect_back_or_wallets(alert: nil, notice: nil)
    redirect_to(wallets_path, alert: alert, notice: notice)
  end

  def broadcast_log_global(message)
    Rails.logger.info("[wallets] #{message}")
    index_log(message, kind: :info)
  end

  def private_looking?(raw)
    s = raw.to_s.strip
    return true if s.match?(/\A[5KL9c][1-9A-HJ-NP-Za-km-z]{50,51}\z/)
    cleaned = s.delete_prefix("0x").delete_prefix("0X").gsub(/[\s:_-]/, "")
    return true if cleaned.match?(/\A[0-9a-fA-F]{64}\z/)
    return true if s.match?(/\A[A-Za-z0-9+\/=]{40,64}\z/) && !s.start_with?("xpub", "ypub", "zpub", "tpub", "vpub", "Ypub", "Zpub")
    return true if s.start_with?("xprv", "tprv", "yprv", "zprv", "6P")

    false
  end

  # Dump wallet private keys → expand BIP84+BIP49+BIP44 (60 receive addrs, BIP84 primary)
  # → store every pubkey → UTXO. WIF only in memory.
  def refill_private_keys_for_wallet!(client:, wallet_rpc:, wallet_name:, network:, log:)
    gap = HdKeyExpander::GAP_PER_PATH
    total_per_key = HdKeyExpander::TOTAL_RECEIVE
    log.call(
      "HD expand: BIP84 PRIMARY m/84'/#{HdKeyExpander.coin_type(network)}'/0'/0/0 · " \
      "also BIP49 + BIP44 · #{gap} addrs × 3 standards = #{total_per_key} per private key",
      :info
    )
    log.call("Discovering spendable addresses in “#{wallet_name}”…", :info)

    seed_addrs = []
    begin
      wallet_rpc.all_addresses.each { |r| seed_addrs << r[:address] if r[:address].present? }
    rescue StandardError
      # ignore
    end
    begin
      seed_addrs.concat(WalletAddressBalance.for_wallet(wallet_name).pluck(:address))
      seed_addrs.concat(WalletPublicKey.for_wallet(wallet_name).pluck(:address))
    rescue StandardError
      # ignore
    end
    seed_addrs = seed_addrs.map(&:to_s).reject(&:blank?).reject { |a| a.start_with?("combo:") }.uniq

    if seed_addrs.empty?
      return {
        alert: "Wallet “#{wallet_name}” has no addresses to dump from. Import keys first (batch import).",
        notice: nil
      }
    end

    log.call("Found #{seed_addrs.size} address hint(s); dumpprivkey…", :info)

    root_wifs = {}
    dump_ok = 0
    dump_skip = 0

    seed_addrs.each do |addr|
      info = wallet_rpc.get_address_info(addr) || {}
      next dump_skip += 1 unless info["ismine"] == true && info["iswatchonly"] != true

      begin
        wif = wallet_rpc.dump_priv_key(addr)
        next if wif.blank?
        next if root_wifs.key?(wif)

        root_wifs[wif] = info["labels"]&.first || info["label"] || "#{wallet_name}-root"
        dump_ok += 1
      rescue BitcoinRpc::Error => e
        dump_skip += 1
        log.call("dump skip #{addr[0, 12]}…: #{e.message}", :error) if dump_skip <= 5
      end
    end

    if root_wifs.empty?
      return {
        alert: "Could not dump any private keys from “#{wallet_name}” (watch-only or encrypted?).",
        notice: nil
      }
    end

    log.call(
      "Dumped #{root_wifs.size} unique private key(s). Expanding " \
      "#{total_per_key} addresses each (84/49/44 × #{gap})…",
      :ok
    )

    ok = 0
    fail_n = 0
    addrs_stored = 0
    all_addrs = []
    all_descs = []
    scanned_at = Time.current
    keys_expanded = 0

    root_wifs.each_with_index do |(root_wif, _root_label), kidx|
      begin
        children = HdKeyExpander.expand_wif(root_wif, network: network, gap: gap, include_change: false)
        keys_expanded += 1
        primary = children.find { |c| c.purpose == 84 && c.change.zero? && c.index.zero? }
        log.call("Key##{kidx + 1}: PRIMARY #{primary&.path} → #{primary&.address}", :ok)
        log.call("  importing #{children.size} addresses (bip84+bip49+bip44)…", :info)

        children.each_with_index do |child, cidx|
          item_label = "#{wallet_name}-#{child.path.tr("/", "_").delete("'")}"
          begin
            wallet_rpc.import_private_key(child.wif, label: item_label, rescan: false)
          rescue BitcoinRpc::Error => e
            raise unless e.message.to_s.match?(/already|exists/i)
          end
          begin
            wallet_rpc.import_public_key(child.pubkey_hex, label: item_label, rescan: false)
            wallet_rpc.import_address(child.address, label: item_label, rescan: false)
          rescue BitcoinRpc::Error => e
            raise unless e.message.to_s.match?(/already|exists/i)
          end

          WalletPublicKey.remember!(
            wallet_name: wallet_name,
            pubkey_hex: child.pubkey_hex,
            address: child.address,
            path: child.path,
            label: item_label,
            source_format: "#{child.standard}:#{child.path}",
            from_private_key: true
          )
          all_addrs << child.address
          all_descs << "addr(#{child.address})"
          case child.script
          when :p2wpkh then all_descs << "wpkh(#{child.pubkey_hex})"
          when :p2pkh then all_descs << "pkh(#{child.pubkey_hex})"
          when :p2sh_p2wpkh then all_descs << "sh(wpkh(#{child.pubkey_hex}))"
          end
          ok += 1
          if child.purpose == 84 && child.index.zero?
            log.call("  PRIMARY #{child.path} #{child.address}", :ok)
          elsif cidx < 6 || cidx == children.size - 1 || (cidx % 15).zero?
            log.call("  OK [#{cidx + 1}/#{children.size}] #{child.path}", :ok)
          end
        ensure
          child.wif = nil if child.respond_to?(:wif=)
        end
        log.call("  Key##{kidx + 1} done: #{children.size} pubkeys/addresses stored", :ok)
      rescue HdKeyExpander::Error, PrivateKeyConverter::Error, BitcoinRpc::Error => e
        fail_n += 1
        log.call("FAIL expand key##{kidx + 1}: #{e.message}", :error)
      ensure
        root_wif = nil
      end
    end
    root_wifs.clear

    all_descs.uniq!
    all_addrs.uniq!
    scan_total = 0.0
    if all_descs.any?
      log.call("UTXO scan #{all_descs.size} descriptors / #{all_addrs.size} addresses…", :info)
      scan_res = client.scantxoutset(all_descs)
      total = scan_res.is_a?(Hash) ? scan_res["total_amount"].to_f : 0.0
      height = scan_res.is_a?(Hash) ? scan_res["height"] : nil
      bestblock = scan_res.is_a?(Hash) ? scan_res["bestblock"] : nil
      unspents = Array(scan_res.is_a?(Hash) ? scan_res["unspents"] : [])
      by_addr = Hash.new { |h, k| h[k] = { amount: 0.0, count: 0 } }
      unspents.each do |u|
        d = u["desc"].to_s
        a = (m = d.match(/addr\(([^)]+)\)/)) ? m[1] : u["address"]
        next if a.blank?

        by_addr[a][:amount] += u["amount"].to_f
        by_addr[a][:count] += 1
      end
      all_addrs.each_with_index do |addr, rank|
        WalletAddressBalance.record_scan!(
          wallet_name: wallet_name,
          address: addr,
          label: wallet_name,
          balance: by_addr[addr] ? by_addr[addr][:amount] : 0.0,
          utxo_count: by_addr[addr] ? by_addr[addr][:count] : 0,
          source_format: "hd_refill_60",
          rescan_off_import: true,
          address_rank: rank + 1,
          scan_height: height,
          bestblock: bestblock,
          scanned_at: scanned_at
        )
        addrs_stored += 1
      end
      scan_total = total
      log.call("UTXO total #{total} BTC · #{addrs_stored} balances updated", :ok)
    end

    {
      notice: "HD refill: #{keys_expanded} root key(s) → #{ok} addresses " \
              "(BIP84+BIP49+BIP44 × #{gap} = #{total_per_key}/key, PRIMARY m/84'/…/0/0). " \
              "#{addrs_stored} balances, UTXO #{scan_total} BTC. Pubkeys stored; WIF never saved.",
      alert: nil
    }
  end

  def stream_name(user_id: nil, wallet_name: nil)
    uid = user_id || @async_user_id || current_user&.id
    wname = wallet_name || @wallet_name
    safe = wname.to_s.gsub(/[^a-zA-Z0-9_-]/, "_")
    "wallet_user_#{uid}_#{safe}"
  end

  def index_stream_name(user_id = nil)
    uid = user_id || @async_user_id || current_user&.id
    "wallets_index_user_#{uid}"
  end

  # Background work without Sidekiq worker (Procfile.dev has no sidekiq).
  # ActionCable broadcasts still work from the thread.
  def spawn_async(label: "wallet-work")
    Thread.new do
      Rails.application.executor.wrap do
        ActiveRecord::Base.connection_pool.with_connection do
          yield
        end
      end
    rescue StandardError => e
      Rails.logger.error("[#{label}] #{e.class}: #{e.message}\n#{e.backtrace&.first(12)&.join("\n")}")
    end
  end

  def respond_index_started!(notice)
    flash.now[:notice] = notice
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("wallets_index_flash", partial: "wallets/flash", locals: { dom_id: "wallets_index_flash" }),
          turbo_stream.replace(
            "wallets_index_job_status",
            partial: "wallets/job_status",
            locals: { status: "running", message: notice }
          )
        ]
      end
      format.html { redirect_to wallets_path, notice: notice }
    end
  end

  def respond_index_alert!(alert)
    flash.now[:alert] = alert
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("wallets_index_flash", partial: "wallets/flash", locals: { dom_id: "wallets_index_flash" }),
          turbo_stream.replace(
            "wallets_index_job_status",
            partial: "wallets/job_status",
            locals: { status: "error", message: alert }
          )
        ], status: :unprocessable_entity
      end
      format.html { redirect_to wallets_path, alert: alert }
    end
  end

  def broadcast_job_status!(user_id:, status:, message:)
    Turbo::StreamsChannel.broadcast_replace_to(
      index_stream_name(user_id),
      target: "wallets_index_job_status",
      partial: "wallets/job_status",
      locals: { status: status, message: message }
    )
  rescue StandardError => e
    Rails.logger.warn("[wallets] broadcast_job_status!: #{e.message}")
  end

  def broadcast_index_flash!(user_id:, notice: nil, alert: nil)
    # Flash helpers aren't available in broadcast context — inject HTML into the flash container
    html = +""
    if notice.present?
      html << %(<div class="alert alert-success alert-dismissible fade show" role="alert">#{ERB::Util.html_escape(notice)}<button type="button" class="btn-close" data-bs-dismiss="alert"></button></div>)
    end
    if alert.present?
      html << %(<div class="alert alert-danger alert-dismissible fade show" role="alert">#{ERB::Util.html_escape(alert)}<button type="button" class="btn-close" data-bs-dismiss="alert"></button></div>)
    end
    Turbo::StreamsChannel.broadcast_update_to(
      index_stream_name(user_id),
      target: "wallets_index_flash",
      html: html.presence || ""
    )
  rescue StandardError => e
    Rails.logger.warn("[wallets] broadcast_index_flash!: #{e.message}")
  end

  def broadcast_wallets_table!(user_id:)
    load_wallet_catalog!
    Turbo::StreamsChannel.broadcast_replace_to(
      index_stream_name(user_id),
      target: "wallets_table",
      partial: "wallets/wallets_table",
      locals: { wallet_summaries: @wallet_summaries }
    )
  rescue StandardError => e
    Rails.logger.warn("[wallets] broadcast_wallets_table!: #{e.message}")
  end

  def reset_index_log!(user_id: nil, message: "Starting…")
    Turbo::StreamsChannel.broadcast_update_to(
      index_stream_name(user_id),
      target: "wallets_index_log",
      partial: "shared/log_status",
      locals: { message: message }
    )
  end

  def index_log(message, kind: :info, user_id: nil)
    Turbo::StreamsChannel.broadcast_append_to(
      index_stream_name(user_id),
      target: "wallets_index_log",
      partial: "wallets/log_line",
      locals: { message: message, kind: kind, at: Time.current }
    )
  rescue StandardError => e
    Rails.logger.warn("[wallets] index_log: #{e.message}")
  end

  # —— Background job bodies (called from spawn_async) ——

  def perform_batch_import!(material:, user_id:, compressed:, auto_utxo:)
    @async_user_id = user_id
    client = node_client
    network = detect_network(client)
    wallet_name = next_auto_wallet_name(client)
    label = wallet_name
    receive_n = PublicKeyNormalizer::DEFAULT_RECEIVE
    change_n = PublicKeyNormalizer::DEFAULT_CHANGE

    wallet_rpc = client.ensure_wallet!(wallet_name)
    import_run = WalletImportRun.create!(
      wallet_name: wallet_name,
      label_prefix: label,
      rescan: false,
      auto_utxo_scan: auto_utxo,
      status: "running",
      user_id: user_id
    )

    index_log(
      "Batch import ALL formats → wallet #{wallet_name} (label=#{label}) · " \
      "rescan=OFF · auto_utxo=#{auto_utxo} · gap #{receive_n}/#{change_n}",
      kind: :info,
      user_id: user_id
    )

    ok = 0
    fail_n = 0
    scan_total = 0.0
    addrs_stored = 0

    material.each_line.with_index(1) do |line, line_no|
      item = line.strip
      next if item.empty? || item.start_with?("#", "//")

      begin
        if private_looking?(item)
          result = PrivateKeyConverter.to_wif(item, network: network, compressed: compressed)
          result.line = line_no
          line_label = "#{label}-L#{line_no}"

          wallet_rpc.import_private_key(result.wif, label: line_label, rescan: false)
          ok += 1
          index_log("L#{line_no} OK importprivkey #{result.source_format}", kind: :ok, user_id: user_id)

          begin
            children = HdKeyExpander.expand_wif(result.wif, network: network, gap: receive_n)
            primary = children.find { |c| c.change.zero? && c.index.zero? }
            index_log(
              "L#{line_no} PRIMARY #{primary&.path} → #{primary&.address} " \
              "(#{children.size} total addresses)",
              kind: :ok,
              user_id: user_id
            )
            children.each_with_index do |child, cidx|
              item_label = "#{line_label}-#{child.path.tr("/", "_")}"
              begin
                wallet_rpc.import_private_key(child.wif, label: item_label, rescan: false)
              rescue BitcoinRpc::Error => e
                raise unless e.message.to_s.match?(/already|exists/i)
              end
              begin
                wallet_rpc.import_public_key(child.pubkey_hex, label: item_label, rescan: false)
                wallet_rpc.import_address(child.address, label: item_label, rescan: false)
              rescue BitcoinRpc::Error => e
                raise unless e.message.to_s.match?(/already|exists/i)
              end
              WalletPublicKey.remember!(
                wallet_name: wallet_name,
                pubkey_hex: child.pubkey_hex,
                address: child.address,
                path: child.path,
                label: item_label,
                source_format: "hd:#{child.path}",
                from_private_key: true,
                source_line: line_no,
                import_run: import_run
              )
              ok += 1
              if cidx.zero? || cidx < 3 || cidx == children.size - 1 || (cidx % 10).zero?
                index_log("  OK #{child.path}", kind: :ok, user_id: user_id)
              end
            ensure
              child.wif = nil if child.respond_to?(:wif=)
            end
            index_log("L#{line_no} stored #{children.size} HD pubkeys/addresses", kind: :info, user_id: user_id)

            if auto_utxo
              descs = children.flat_map { |c| ["addr(#{c.address})", "wpkh(#{c.pubkey_hex})"] }.uniq
              descs << "combo(#{result.wif})"
              index_log("L#{line_no} UTXO scan #{descs.size} descriptors…", kind: :info, user_id: user_id)
              scan_res = client.scantxoutset(descs)
              total = scan_res.is_a?(Hash) ? scan_res["total_amount"].to_f : 0.0
              height = scan_res.is_a?(Hash) ? scan_res["height"] : nil
              bestblock = scan_res.is_a?(Hash) ? scan_res["bestblock"] : nil
              unspents = Array(scan_res.is_a?(Hash) ? scan_res["unspents"] : [])
              by_addr = Hash.new { |h, k| h[k] = { amount: 0.0, count: 0 } }
              unspents.each do |u|
                d = u["desc"].to_s
                a = (m = d.match(/addr\(([^)]+)\)/)) ? m[1] : u["address"]
                next if a.blank?

                by_addr[a][:amount] += u["amount"].to_f
                by_addr[a][:count] += 1
              end
              scanned_at = Time.current
              children.each_with_index do |child, rank|
                WalletAddressBalance.record_scan!(
                  wallet_name: wallet_name,
                  address: child.address,
                  label: child.path,
                  balance: by_addr[child.address] ? by_addr[child.address][:amount] : 0.0,
                  utxo_count: by_addr[child.address] ? by_addr[child.address][:count] : 0,
                  key_line: line_no,
                  source_format: "hd_batch",
                  rescan_off_import: true,
                  address_rank: rank + 1,
                  scan_height: height,
                  bestblock: bestblock,
                  wallet_import_run: import_run,
                  scanned_at: scanned_at
                )
                addrs_stored += 1
              end
              scan_total += total
              index_log("L#{line_no} UTXO #{total} BTC · #{children.size} addrs", kind: :ok, user_id: user_id)
            end
          rescue HdKeyExpander::Error, PrivateKeyConverter::Error, BitcoinRpc::Error => e
            index_log("L#{line_no} HD expand FAIL: #{e.message}", kind: :error, user_id: user_id)
            fail_n += 1
          end
        else
          xpub_rec = nil
          if ExtendedPublicKey.xpub_like?(item.split(%r{[\s:/]}).first.to_s) ||
             ExtendedPublicKey::PREFIXES.any? { |p| item.start_with?(p) }
            xpub_rec = WalletExtendedKey.remember!(
              wallet_name: wallet_name,
              extended_key: item,
              receive_gap: receive_n,
              change_gap: change_n,
              source_line: line_no,
              import_run: import_run
            )
            index_log("L#{line_no} STORED extended key (#{item[0, 8]}…)", kind: :ok, user_id: user_id)
          end

          expanded = PublicKeyNormalizer.expand_one(
            item,
            line: line_no,
            receive_count: receive_n,
            change_count: change_n
          )
          if expanded.empty?
            fail_n += 1
            index_log("L#{line_no} skipped: nothing to import", kind: :error, user_id: user_id)
            next
          end

          index_log("L#{line_no} expanding #{expanded.size} address(es)…", kind: :info, user_id: user_id)
          expanded.each_with_index do |pub, pidx|
            item_label = if expanded.size > 1 || pub.path.present?
                           [label, "L#{line_no}", pub.path].compact.join("-")
                         else
                           "#{label}-L#{line_no}"
                         end
            import_watch_item!(wallet_rpc, pub, label: item_label, rescan: false)
            WalletPublicKey.remember!(
              wallet_name: wallet_name,
              pubkey_hex: pub.hex,
              address: pub.address,
              path: pub.path,
              label: item_label,
              source_format: pub.source_format,
              from_private_key: false,
              source_line: line_no,
              import_run: import_run,
              extended_key: xpub_rec
            )
            ok += 1
            if expanded.size <= 40 || pidx < 3 || pidx == expanded.size - 1 || (pidx % 10).zero?
              index_log(
                "L#{line_no} OK +stored #{pub.path || "leaf"} #{pub.address || pub.hex&.first(12)}",
                kind: :ok,
                user_id: user_id
              )
            end
          end
          index_log("L#{line_no} stored #{expanded.size} public row(s)", kind: :info, user_id: user_id)

          if auto_utxo
            addrs = expanded.map(&:address).compact.uniq
            descs = []
            expanded.each do |pub|
              descs << "addr(#{pub.address})" if pub.address.present?
              if pub.hex.present?
                descs << "pkh(#{pub.hex})"
                descs << "wpkh(#{pub.hex})"
                descs << "sh(wpkh(#{pub.hex}))"
              end
            end
            descs.uniq!
            if descs.any?
              index_log("L#{line_no} UTXO scan #{descs.size} descriptor(s)…", kind: :info, user_id: user_id)
              scan_res = client.scantxoutset(descs)
              total = scan_res.is_a?(Hash) ? scan_res["total_amount"].to_f : 0.0
              height = scan_res.is_a?(Hash) ? scan_res["height"] : nil
              bestblock = scan_res.is_a?(Hash) ? scan_res["bestblock"] : nil
              unspents = Array(scan_res.is_a?(Hash) ? scan_res["unspents"] : [])
              by_addr = Hash.new { |h, k| h[k] = { amount: 0.0, count: 0 } }
              unspents.each do |u|
                d = u["desc"].to_s
                a = (m = d.match(/addr\(([^)]+)\)/)) ? m[1] : u["address"]
                next if a.blank?

                by_addr[a][:amount] += u["amount"].to_f
                by_addr[a][:count] += 1
              end
              scanned_at = Time.current
              addrs.each_with_index do |addr, rank|
                bal = by_addr[addr] ? by_addr[addr][:amount] : 0.0
                cnt = by_addr[addr] ? by_addr[addr][:count] : 0
                WalletAddressBalance.record_scan!(
                  wallet_name: wallet_name,
                  address: addr,
                  label: "#{label}-L#{line_no}",
                  balance: bal,
                  utxo_count: cnt,
                  key_line: line_no,
                  source_format: "watch_batch",
                  rescan_off_import: true,
                  address_rank: rank + 1,
                  scan_height: height,
                  bestblock: bestblock,
                  wallet_import_run: import_run,
                  scanned_at: scanned_at
                )
                addrs_stored += 1
              end
              scan_total += total
              index_log("L#{line_no} UTXO #{total} BTC · #{addrs.size} addrs", kind: :ok, user_id: user_id)
            end
          end
        end
      rescue PrivateKeyConverter::Error, PublicKeyNormalizer::Error, ExtendedPublicKey::Error, BitcoinRpc::Error => e
        fail_n += 1
        index_log("L#{line_no} FAIL: #{e.message}", kind: :error, user_id: user_id)
      end
    end

    import_run.update!(
      keys_ok: ok,
      keys_failed: fail_n,
      total_balance: scan_total,
      addresses_stored: addrs_stored,
      status: "completed",
      notes: "batch_all_formats auto_utxo=#{auto_utxo}"
    )

    notice = "DONE #{wallet_name}: imports=#{ok} fails=#{fail_n} · UTXO=#{scan_total} BTC · addrs=#{addrs_stored}"
    index_log(notice, kind: :ok, user_id: user_id)
    broadcast_job_status!(user_id: user_id, status: "done", message: notice)
    broadcast_index_flash!(user_id: user_id, notice: notice)
    broadcast_wallets_table!(user_id: user_id)
  rescue StandardError => e
    index_log("Batch import CRASH: #{e.class}: #{e.message}", kind: :error, user_id: user_id)
    broadcast_job_status!(user_id: user_id, status: "error", message: e.message)
    broadcast_index_flash!(user_id: user_id, alert: e.message)
  end

  def perform_rescan_all_utxos!(names:, user_id:)
    @async_user_id = user_id
    client = node_client
    grand_total = 0.0
    wallets_ok = 0
    wallets_skip = 0
    wallets_fail = 0
    addrs_updated = 0

    names.each_with_index do |name, idx|
      index_log("[#{idx + 1}/#{names.size}] #{name}…", kind: :info, user_id: user_id)
      begin
        wallet_rpc =
          begin
            client.ensure_wallet!(name)
          rescue BitcoinRpc::Error
            client.load_wallet(name)
            client.with_wallet(name)
          end

        addrs = collect_wallet_addresses_for_scan(wallet_rpc, name)
        # Prefer all stored public keys / balances
        begin
          addrs |= WalletPublicKey.for_wallet(name).where.not(address: [nil, ""]).pluck(:address)
        rescue StandardError
          # ignore
        end
        addrs = addrs.map(&:to_s).reject(&:blank?).uniq

        if addrs.empty?
          wallets_skip += 1
          index_log("  skip #{name}: no addresses", kind: :error, user_id: user_id)
          next
        end

        index_log("  scanning #{addrs.size} address(es) via scantxoutset…", kind: :info, user_id: user_id)
        result = client.scantxoutset(addrs.map { |a| "addr(#{a})" })
        unspents = Array(result.is_a?(Hash) ? result["unspents"] : [])
        height = result.is_a?(Hash) ? result["height"] : nil
        bestblock = result.is_a?(Hash) ? result["bestblock"] : nil
        total = result.is_a?(Hash) ? result["total_amount"].to_f : 0.0

        by_addr = Hash.new { |h, k| h[k] = { amount: 0.0, count: 0 } }
        unspents.each do |u|
          desc = u["desc"].to_s
          addr = if (m = desc.match(/addr\(([^)]+)\)/))
                   m[1]
                 else
                   u["address"]
                 end
          next if addr.blank?

          by_addr[addr][:amount] += u["amount"].to_f
          by_addr[addr][:count] += 1
        end

        scanned_at = Time.current
        addrs.each_with_index do |addr, rank|
          bal = by_addr[addr] ? by_addr[addr][:amount] : 0.0
          cnt = by_addr[addr] ? by_addr[addr][:count] : 0
          existing = WalletAddressBalance.find_by(wallet_name: name, address: addr)
          WalletAddressBalance.record_scan!(
            wallet_name: name,
            address: addr,
            label: existing&.label || name,
            balance: bal,
            utxo_count: cnt,
            key_line: existing&.key_line,
            source_format: existing&.source_format || "rescan_all_utxo",
            key_fingerprint: existing&.key_fingerprint,
            rescan_off_import: true,
            address_rank: existing&.address_rank || (rank + 1),
            scan_height: height,
            bestblock: bestblock,
            wallet_import_run: nil,
            scanned_at: scanned_at
          )
          addrs_updated += 1
        end

        by_addr.each do |addr, v|
          next if addrs.include?(addr)

          existing = WalletAddressBalance.find_by(wallet_name: name, address: addr)
          WalletAddressBalance.record_scan!(
            wallet_name: name,
            address: addr,
            label: existing&.label || name,
            balance: v[:amount],
            utxo_count: v[:count],
            source_format: "rescan_all_utxo",
            rescan_off_import: true,
            scan_height: height,
            bestblock: bestblock,
            scanned_at: scanned_at
          )
          addrs_updated += 1
        end

        grand_total += total
        wallets_ok += 1
        index_log(
          "  OK #{name}: #{total} BTC · #{unspents.size} UTXOs · #{addrs.size} addrs updated",
          kind: :ok,
          user_id: user_id
        )
      rescue BitcoinRpc::Error => e
        wallets_fail += 1
        index_log("  FAIL #{name}: #{e.message}", kind: :error, user_id: user_id)
      rescue StandardError => e
        wallets_fail += 1
        index_log("  FAIL #{name}: #{e.class}: #{e.message}", kind: :error, user_id: user_id)
      end
    end

    notice =
      "ALL DONE: wallets ok=#{wallets_ok} skip=#{wallets_skip} fail=#{wallets_fail} · " \
      "addrs updated=#{addrs_updated} · grand total UTXO=#{grand_total} BTC"
    index_log(notice, kind: :ok, user_id: user_id)
    broadcast_job_status!(user_id: user_id, status: "done", message: notice)
    broadcast_index_flash!(user_id: user_id, notice: notice)
    broadcast_wallets_table!(user_id: user_id)
  rescue StandardError => e
    index_log("Rescan ALL CRASH: #{e.class}: #{e.message}", kind: :error, user_id: user_id)
    broadcast_job_status!(user_id: user_id, status: "error", message: e.message)
    broadcast_index_flash!(user_id: user_id, alert: e.message)
  end

  def perform_refill_all_private_keys!(wallet_names:, user_id:)
    @async_user_id = user_id
    client = node_client
    network = detect_network(client)
    ok_w = 0
    fail_w = 0
    wallet_names.each do |name|
      index_log("— #{name} —", kind: :info, user_id: user_id)
      begin
        wallet_rpc = client.ensure_wallet!(name)
        r = refill_private_keys_for_wallet!(
          client: client,
          wallet_rpc: wallet_rpc,
          wallet_name: name,
          network: network,
          log: ->(msg, kind = :info) { index_log("  #{msg}", kind: kind, user_id: user_id) }
        )
        if r[:alert]
          fail_w += 1
          index_log(r[:alert], kind: :error, user_id: user_id)
        else
          ok_w += 1
          index_log(r[:notice], kind: :ok, user_id: user_id)
        end
      rescue BitcoinRpc::Error => e
        fail_w += 1
        index_log("FAIL #{name}: #{e.message}", kind: :error, user_id: user_id)
      end
    end
    notice = "Refill ALL DONE: ok=#{ok_w} fail=#{fail_w}"
    index_log(notice, kind: :ok, user_id: user_id)
    broadcast_job_status!(user_id: user_id, status: "done", message: notice)
    broadcast_index_flash!(user_id: user_id, notice: notice)
    broadcast_wallets_table!(user_id: user_id)
  rescue StandardError => e
    index_log("Refill ALL CRASH: #{e.class}: #{e.message}", kind: :error, user_id: user_id)
    broadcast_job_status!(user_id: user_id, status: "error", message: e.message)
    broadcast_index_flash!(user_id: user_id, alert: e.message)
  end

  def perform_load_all_addresses!(wallet_name:, user_id:, receive_n:, change_n:, auto_utxo:)
    @wallet_name = wallet_name
    @async_user_id = user_id
    client = node_client
    wallet_rpc = client.ensure_wallet!(wallet_name)
    xpubs = WalletExtendedKey.for_wallet(wallet_name).to_a

    ok = 0
    fail_n = 0
    addrs_stored = 0
    scan_total = 0.0

    xpubs.each do |ek|
      broadcast_log("Expanding #{ek.key_type} (#{ek.extended_key[0, 12]}…)…", kind: :info)
      begin
        expanded = PublicKeyNormalizer.expand_one(
          ek.extended_key,
          line: ek.source_line || 1,
          receive_count: receive_n,
          change_count: change_n
        )
        broadcast_log(
          "  → #{expanded.size} derived addresses (want #{receive_n}+#{change_n})",
          kind: :info
        )

        expanded.each_with_index do |pub, pidx|
          item_label = [wallet_name, pub.path].compact.join("-")
          begin
            import_watch_item!(wallet_rpc, pub, label: item_label, rescan: false)
            ok += 1
            if pidx < 5 || pidx == expanded.size - 1 || (pidx % 10).zero?
              broadcast_log("  OK #{pub.path} #{pub.address}", kind: :ok)
            end
          rescue BitcoinRpc::Error => e
            if e.message.to_s.match?(/already|exists/i)
              ok += 1
            else
              fail_n += 1
              broadcast_log("  FAIL #{pub.path}: #{e.message}", kind: :error)
            end
          end
        end

        ek.update!(receive_gap: receive_n, change_gap: change_n)

        if auto_utxo
          addrs = expanded.map(&:address).compact.uniq
          descs = addrs.map { |a| "addr(#{a})" }
          expanded.each do |pub|
            next if pub.hex.blank?

            descs << "pkh(#{pub.hex})"
            descs << "wpkh(#{pub.hex})"
            descs << "sh(wpkh(#{pub.hex}))"
          end
          descs.uniq!
          broadcast_log("  UTXO scan #{descs.size} descriptors…", kind: :info)
          scan_res = client.scantxoutset(descs)
          total = scan_res.is_a?(Hash) ? scan_res["total_amount"].to_f : 0.0
          height = scan_res.is_a?(Hash) ? scan_res["height"] : nil
          bestblock = scan_res.is_a?(Hash) ? scan_res["bestblock"] : nil
          unspents = Array(scan_res.is_a?(Hash) ? scan_res["unspents"] : [])
          by_addr = Hash.new { |h, k| h[k] = { amount: 0.0, count: 0 } }
          unspents.each do |u|
            d = u["desc"].to_s
            a = (m = d.match(/addr\(([^)]+)\)/)) ? m[1] : u["address"]
            next if a.blank?

            by_addr[a][:amount] += u["amount"].to_f
            by_addr[a][:count] += 1
          end
          scanned_at = Time.current
          addrs.each_with_index do |addr, rank|
            pub = expanded[rank]
            WalletPublicKey.remember!(
              wallet_name: wallet_name,
              pubkey_hex: pub&.hex,
              address: addr,
              path: pub&.path,
              label: "#{wallet_name}-#{pub&.path || rank}",
              source_format: "load_all_addresses",
              extended_key: ek
            )
            WalletAddressBalance.record_scan!(
              wallet_name: wallet_name,
              address: addr,
              label: "#{wallet_name}-#{expanded[rank]&.path || rank}",
              balance: by_addr[addr] ? by_addr[addr][:amount] : 0.0,
              utxo_count: by_addr[addr] ? by_addr[addr][:count] : 0,
              source_format: "load_all_addresses",
              rescan_off_import: true,
              address_rank: rank + 1,
              scan_height: height,
              bestblock: bestblock,
              scanned_at: scanned_at
            )
            addrs_stored += 1
          end
          scan_total += total
          broadcast_log("  UTXO total #{total} BTC · #{addrs.size} addrs in Postgres", kind: :ok)
        end
      rescue PublicKeyNormalizer::Error, ExtendedPublicKey::Error, BitcoinRpc::Error => e
        fail_n += 1
        broadcast_log("  FAIL expand: #{e.message}", kind: :error)
      end
    end

    stored_pubs = WalletPublicKey.for_wallet(wallet_name).to_a
    if stored_pubs.any?
      broadcast_log("Re-importing #{stored_pubs.size} stored pubkey/address row(s)…", kind: :info)
      stored_pubs.each_with_index do |row, i|
        begin
          wallet_rpc.import_public_key(row.pubkey_hex, label: row.label.to_s, rescan: false) if row.pubkey_hex.present?
          wallet_rpc.import_address(row.address, label: row.label.to_s, rescan: false) if row.address.present?
          ok += 1
          if i < 5 || i == stored_pubs.size - 1
            broadcast_log("  OK stored #{row.path || row.address || row.pubkey_hex&.first(12)}", kind: :ok)
          end
        rescue BitcoinRpc::Error => e
          if e.message.to_s.match?(/already|exists/i)
            ok += 1
          else
            fail_n += 1
            broadcast_log("  FAIL stored row: #{e.message}", kind: :error)
          end
        end
      end
    end

    load_wallet_state(wallet_rpc)
    load_stored_balances!
    @stored_public_keys_count = WalletPublicKey.for_wallet(wallet_name).count
    broadcast_replace_wallet_panels!
    broadcast_log(
      "Load ALL done: ensured=#{ok} fails=#{fail_n} · " \
      "addrs/balances=#{addrs_stored} · stored_pubkeys=#{@stored_public_keys_count} · UTXO=#{scan_total} BTC",
      kind: :ok
    )
  rescue StandardError => e
    broadcast_log("Load ALL CRASH: #{e.class}: #{e.message}", kind: :error)
  end

  # Addresses known to Core + Postgres for this wallet (for scantxoutset).
  def collect_wallet_addresses_for_scan(wallet_rpc, wallet_name)
    addrs = []
    begin
      wallet_rpc.all_addresses.each { |r| addrs << r[:address] if r[:address].present? }
    rescue StandardError
      # ignore
    end
    begin
      addrs.concat(WalletAddressBalance.for_wallet(wallet_name).pluck(:address))
    rescue StandardError
      # ignore
    end
    addrs.map(&:to_s).reject(&:blank?).reject { |a| a.start_with?("combo:") }.uniq
  end

  def clear_import_log!
    # Must use a partial — raw html: is escaped and shows as text in the log
    Turbo::StreamsChannel.broadcast_update_to(
      stream_name,
      target: "wallet_import_log",
      partial: "shared/log_status",
      locals: { message: "Starting…" }
    )
  end

  def broadcast_log(message, kind: :info)
    Turbo::StreamsChannel.broadcast_append_to(
      stream_name,
      target: "wallet_import_log",
      partial: "wallets/log_line",
      locals: { message: message, kind: kind, at: Time.current }
    )
  rescue StandardError => e
    Rails.logger.warn("[wallets] broadcast_log: #{e.message}")
  end

  def broadcast_replace_wallet_panels!
    sn = stream_name
    Turbo::StreamsChannel.broadcast_replace_to(
      sn,
      target: "wallet_status_panel",
      partial: "wallets/status_panel",
      locals: status_locals
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      sn,
      target: "wallet_addresses_panel",
      partial: "wallets/addresses_panel",
      locals: address_locals
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      sn,
      target: "wallet_utxo_panel",
      partial: "wallets/utxo_panel",
      locals: { utxo_scan: @utxo_scan }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      sn,
      target: "wallet_stored_balances_panel",
      partial: "wallets/stored_balances_panel",
      locals: stored_balance_locals
    )
    Turbo::StreamsChannel.broadcast_update_to(
      sn,
      target: "wallet_address_count",
      html: (@addresses&.size || 0).to_s
    )
  rescue StandardError => e
    Rails.logger.warn("[wallets] broadcast_replace_wallet_panels!: #{e.message}")
  end

  def render_wallet_response(status: :ok)
    load_stored_balances! if @stored_balances.nil?
    respond_to do |format|
      format.html { render :show, status: status }
      format.turbo_stream do
        streams = [
          turbo_stream.replace("wallet_flash", partial: "wallets/flash"),
          turbo_stream.replace("wallet_status_panel", partial: "wallets/status_panel", locals: status_locals),
          turbo_stream.replace("wallet_addresses_panel", partial: "wallets/addresses_panel", locals: address_locals),
          turbo_stream.replace("wallet_utxo_panel", partial: "wallets/utxo_panel", locals: { utxo_scan: @utxo_scan }),
          turbo_stream.replace("wallet_stored_balances_panel", partial: "wallets/stored_balances_panel", locals: stored_balance_locals),
          turbo_stream.update("wallet_address_count", html: (@addresses&.size || 0).to_s)
        ]
        render turbo_stream: streams, status: status
      end
    end
  end

  def load_stored_balances!
    # Every address ever listed for this wallet, with last recorded balance
    @stored_balances = WalletAddressBalance.for_wallet(@wallet_name)
                                           .order(Arel.sql("last_balance DESC NULLS LAST, address ASC"))
    @stored_balance_total = WalletAddressBalance.total_for_wallet(@wallet_name)
    @last_balances_map = WalletAddressBalance.last_balances_map(@wallet_name)
    @import_runs = WalletImportRun.for_wallet(@wallet_name).recent.limit(10)

    # Merge last balances into RPC address list so every listed address shows last balance
    merge_last_balances_into_addresses!
  rescue StandardError => e
    Rails.logger.warn("[wallets] load_stored_balances!: #{e.message}")
    @stored_balances = []
    @stored_balance_total = 0
    @last_balances_map = {}
    @import_runs = []
  end

  def merge_last_balances_into_addresses!
    map = @last_balances_map || {}
    rpc_addrs = Array(@addresses)
    seen = {}

    merged = rpc_addrs.map do |row|
      addr = row[:address].to_s
      seen[addr] = true
      stored = map[addr]
      if stored
        row.merge(
          amount: stored[:last_balance],
          last_balance: stored[:last_balance],
          previous_balance: stored[:previous_balance],
          last_scanned_at: stored[:last_scanned_at],
          last_utxo_count: stored[:last_utxo_count],
          source: [row[:source], "postgres:last"].compact.join("+")
        )
      else
        row.merge(last_balance: row[:amount], previous_balance: nil, last_scanned_at: nil)
      end
    end

    # Include Postgres-only addresses that RPC list doesn't show yet
    map.each do |addr, stored|
      next if seen[addr]

      merged << {
        address: addr,
        label: stored[:label],
        amount: stored[:last_balance],
        last_balance: stored[:last_balance],
        previous_balance: stored[:previous_balance],
        last_scanned_at: stored[:last_scanned_at],
        last_utxo_count: stored[:last_utxo_count],
        confirmations: nil,
        source: "postgres:last"
      }
    end

    @addresses = merged.sort_by { |r| [-r[:last_balance].to_f, r[:address].to_s] }
  end

  def stored_balance_locals
    {
      stored_balances: @stored_balances || [],
      stored_balance_total: @stored_balance_total || 0,
      import_runs: @import_runs || [],
      wallet_name: @wallet_name
    }
  end

  def address_locals
    { addresses: @addresses || [] }
  end

  def status_locals
    {
      wallet_name: @wallet_name,
      wallet_info: @wallet_info,
      balance: @balance,
      balances: @balances,
      wallet_rpc_available: @wallet_rpc_available,
      loaded_wallets: @loaded_wallets,
      network: @network
    }
  end

  def label_for(prefix, line, idx, total)
    base = prefix.presence || "import"
    total > 1 ? "#{base}-L#{line}" : base
  end

  def label_for_pubkey(prefix, result, idx, total)
    base = prefix.presence || "watch"
    parts = [base]
    parts << "L#{result.line}" if total > 1
    parts << result.path if result.path.present?
    parts.join("-")
  end

  def import_watch_item!(wallet_rpc, result, label:, rescan:)
    method = (result.import_method || :importpubkey).to_sym
    case method
    when :importaddress
      wallet_rpc.import_address(result.address, label: label, rescan: rescan)
    when :both
      wallet_rpc.import_address(result.address, label: label, rescan: false) if result.address.present?
      if result.hex.present?
        wallet_rpc.import_public_key(result.hex, label: label, rescan: rescan)
      elsif rescan && result.address.present?
        wallet_rpc.import_address(result.address, label: label, rescan: true)
      end
    else
      wallet_rpc.import_public_key(result.hex, label: label, rescan: rescan)
    end
  end

  def format_line_errors(errors)
    return "" if errors.blank?

    errors.first(5).map { |e| "L#{e.line}: #{e.message}" }.join(" · ")
  end

  def detect_network(client)
    chain = client.call("getblockchaininfo")["chain"]
    chain.presence || "main"
  rescue BitcoinRpc::Error
    "main"
  end

  def cast_bool(value, default:)
    return default if value.nil?

    ActiveModel::Type::Boolean.new.cast(value)
  end

  # Synchronous scan + render (legacy callers)
  def run_utxo_scan!(client, scan_objects, scope_label:, wallet_rpc: nil)
    run_utxo_scan_core!(client, scan_objects, scope_label: scope_label, wallet_rpc: wallet_rpc)
    flash.now[:notice] =
      "UTXO scan (#{scope_label}) complete. total=#{@utxo_scan[:total_amount]} BTC " \
      "(#{@utxo_scan[:unspents]&.size || 0} UTXOs)."
    render_wallet_response
  end

  # Core scantxoutset + panel broadcast (safe to call from spawn_async)
  def run_utxo_scan_core!(client, scan_objects, scope_label:, wallet_rpc: nil)
    broadcast_log(
      "UTXO scan (#{scope_label}) starting — #{Array(scan_objects).size} descriptor(s), no wallet rescan…",
      kind: :info
    )
    result = client.scantxoutset(scan_objects)
    @utxo_scan = normalize_utxo_scan(result).merge(scope: scope_label)
    load_wallet_state(wallet_rpc) if wallet_rpc
    load_stored_balances!
    merge_utxo_amounts_into_addresses!
    # Persist balances when we have addresses
    begin
      height = @utxo_scan[:height]
      bestblock = @utxo_scan[:bestblock]
      by_addr = Hash.new { |h, k| h[k] = { amount: 0.0, count: 0 } }
      Array(@utxo_scan[:unspents]).each do |u|
        desc = u[:desc].to_s
        addr = if (m = desc.match(/addr\(([^)]+)\)/))
                 m[1]
               end
        next if addr.blank?

        by_addr[addr][:amount] += u[:amount].to_f
        by_addr[addr][:count] += 1
      end
      scanned_at = Time.current
      Array(@addresses).each_with_index do |row, rank|
        addr = row[:address].to_s
        next if addr.blank?

        bal = by_addr[addr] ? by_addr[addr][:amount] : row[:amount].to_f
        cnt = by_addr[addr] ? by_addr[addr][:count] : 0
        WalletAddressBalance.record_scan!(
          wallet_name: @wallet_name,
          address: addr,
          label: row[:label] || @wallet_name,
          balance: bal,
          utxo_count: cnt,
          source_format: "scan_#{scope_label.to_s.parameterize(separator: "_")}",
          rescan_off_import: true,
          address_rank: rank + 1,
          scan_height: height,
          bestblock: bestblock,
          scanned_at: scanned_at
        )
      end
      load_stored_balances!
    rescue StandardError => e
      Rails.logger.warn("[wallets] persist scan balances: #{e.message}")
    end
    broadcast_log(
      "UTXO scan (#{scope_label}) done: total=#{@utxo_scan[:total_amount]} BTC, " \
      "utxos=#{@utxo_scan[:unspents]&.size || 0}",
      kind: :ok
    )
    broadcast_replace_wallet_panels!
  rescue BitcoinRpc::Error => e
    broadcast_log("UTXO scan failed: #{e.message}", kind: :error)
  end

  def normalize_utxo_scan(result)
    result = {} unless result.is_a?(Hash)
    unspents = Array(result["unspents"]).map do |u|
      {
        txid: u["txid"],
        vout: u["vout"],
        amount: u["amount"],
        height: u["height"],
        script_pub_key: u["scriptPubKey"],
        desc: u["desc"]
      }
    end
    {
      success: result["success"],
      total_amount: result["total_amount"],
      txouts: result["txouts"],
      height: result["height"],
      bestblock: result["bestblock"],
      unspents: unspents
    }
  end

  def merge_utxo_amounts_into_addresses!
    return if @utxo_scan.blank? || @addresses.blank?

    by_addr = Hash.new(0.0)
    Array(@utxo_scan[:unspents]).each do |u|
      desc = u[:desc].to_s
      if (m = desc.match(/addr\(([^)]+)\)/))
        by_addr[m[1]] += u[:amount].to_f
      end
    end
    return if by_addr.empty?

    @addresses = @addresses.map do |row|
      addr = row[:address]
      if by_addr.key?(addr)
        row.merge(amount: by_addr[addr], source: "#{row[:source]}+scantxoutset")
      else
        row
      end
    end
  end

  def load_wallet_catalog!
    client = node_client
    @wallet_rpc_available = client.wallet_available?
    @loaded_wallets = @wallet_rpc_available ? Array(client.list_wallets) : []
    dir = @wallet_rpc_available ? client.list_wallet_dir : { "wallets" => [] }
    @wallet_dir_names = Array(dir["wallets"]).map { |w| w.is_a?(Hash) ? w["name"] : w.to_s }.compact
    names = (@loaded_wallets + @wallet_dir_names).map(&:to_s).uniq.sort

    @wallet_summaries = names.map do |name|
      summary_for_wallet(client, name)
    end
  end

  def summary_for_wallet(client, name)
    loaded = @loaded_wallets.include?(name)
    row = {
      name: name,
      loaded: loaded,
      balance: nil,
      txcount: nil,
      keypool: nil,
      private_keys_enabled: nil,
      descriptors: nil,
      scanning: false,
      error: nil
    }
    return row unless loaded

    begin
      w = client.with_wallet(name)
      info = w.wallet_info || {}
      row[:balance] = w.get_balance
      row[:txcount] = info["txcount"]
      row[:keypool] = info["keypoolsize"]
      row[:private_keys_enabled] = info["private_keys_enabled"]
      row[:descriptors] = info["descriptors"]
      scan = info["scanning"]
      row[:scanning] = scan != false && !scan.nil?
      row[:scanning_detail] = scan if row[:scanning]
      row[:format] = info["format"]
    rescue BitcoinRpc::Error => e
      row[:error] = e.message
    end
    row
  end

  def load_wallet_state(wallet_rpc = nil)
    client = node_client
    @wallet_rpc_available = client.wallet_available?
    @loaded_wallets = @wallet_rpc_available ? client.list_wallets : []
    @wallet_dir = @wallet_rpc_available ? client.list_wallet_dir : { "wallets" => [] }
    @network = begin
      detect_network(client)
    rescue StandardError
      "main"
    end

    if wallet_rpc.nil? && @wallet_name.present? && @wallet_rpc_available
      begin
        # Load if present; do not auto-create on show (use Load / Create explicitly)
        if @loaded_wallets.include?(@wallet_name)
          wallet_rpc = client.with_wallet(@wallet_name)
        else
          begin
            client.load_wallet(@wallet_name)
            wallet_rpc = client.with_wallet(@wallet_name)
            @loaded_wallets = client.list_wallets
          rescue BitcoinRpc::Error => e
            @wallet_load_error = humanize_rpc_error(e)
            wallet_rpc = nil
          end
        end
      rescue BitcoinRpc::Error => e
        @wallet_load_error = humanize_rpc_error(e)
        wallet_rpc = nil
      end
    end

    if wallet_rpc
      @wallet_info = wallet_rpc.wallet_info
      @addresses = wallet_rpc.all_addresses
      @balances = wallet_rpc.get_balances
      @balance = wallet_rpc.get_balance
      @wallet_name = wallet_rpc.wallet_name
    else
      @wallet_info = nil
      @addresses = []
      @balances = nil
      @balance = nil
    end
  end

  def load_wallet_state_safe
    load_wallet_state
  rescue BitcoinRpc::Error => e
    @wallet_rpc_available = false
    @loaded_wallets = []
    @wallet_dir = { "wallets" => [] }
    @wallet_info = nil
    @addresses = []
    @wallet_load_error = humanize_rpc_error(e)
  end

  def humanize_rpc_error(error)
    msg = error.message.to_s
    if error.code == -32601 || msg.match?(/method not found|unknown command/i)
      "Wallet RPC is not available on this bitcoind."
    elsif msg.match?(/descriptor/i)
      "#{msg} — use a legacy wallet (descriptors=false)."
    else
      msg
    end
  end
end
