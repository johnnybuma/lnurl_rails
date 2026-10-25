# frozen_string_literal: true

# Scan-only UTXO balances via node scantxoutset.
# Never creates a wallet, never imports keys, never writes to Postgres.
class UtxoScansController < ApplicationController
  before_action :require_admin!

  def show
    @network = detect_network
    @compressed = true
    @derive_receive = UtxoScanBuilder::DEFAULT_RECEIVE
    @derive_change = UtxoScanBuilder::DEFAULT_CHANGE
    @mode = "auto"
    @scan_result = nil
  end

  def create
    @network = detect_network
    @compressed = cast_bool(params[:compressed], default: true)
    @derive_receive = (params[:derive_receive].presence || UtxoScanBuilder::DEFAULT_RECEIVE).to_i
    @derive_change = (params[:derive_change].presence || UtxoScanBuilder::DEFAULT_CHANGE).to_i
    @mode = params[:mode].presence || "auto"
    raw = params[:material].to_s

    if raw.strip.blank?
      flash.now[:alert] = "Paste private keys, pubkeys, xpubs, and/or addresses to scan."
      return render_scan_response(status: :unprocessable_entity)
    end

    built = UtxoScanBuilder.build(
      raw,
      network: @network,
      compressed: @compressed,
      receive_count: @derive_receive,
      change_count: @derive_change,
      mode: @mode
    )

    @build_errors = built[:errors]
    @scan_items = built[:items]

    if built[:descriptors].empty?
      flash.now[:alert] =
        "No valid scan targets. #{format_errors(built[:errors])}"
      return render_scan_response(status: :unprocessable_entity)
    end

    reset_scan_log!
    broadcast_scan_log(
      "Scan-only: #{built[:descriptors].size} descriptor(s), " \
      "#{built[:errors].size} line error(s). No wallet · no import · no Postgres.",
      kind: :info
    )
    built[:errors].first(20).each do |err|
      broadcast_scan_log("L#{err[:line]} skipped (#{err[:preview]}): #{err[:message]}", kind: :error)
    end

    broadcast_scan_log(
      "Calling scantxoutset (#{built[:descriptors].size} descriptors) — this can take a few minutes…",
      kind: :info
    )

    client = node_rpc
    # Chunk large scans so the live log can show progress
    result = run_scantxoutset_with_progress(client, built[:descriptors])
    @scan_result = normalize_result(result, items: built[:items])

    broadcast_scan_log(
      "Done: total=#{@scan_result[:total_amount]} BTC · " \
      "#{@scan_result[:unspents].size} UTXO(s) · height=#{@scan_result[:height]}",
      kind: :ok
    )
    broadcast_scan_table!

    flash.now[:notice] =
      "Scan-only complete: #{@scan_result[:total_amount]} BTC " \
      "(#{@scan_result[:unspents].size} UTXOs). Nothing was imported or stored."
    render_scan_response
  rescue BitcoinRpc::Error => e
    flash.now[:alert] = e.message
    broadcast_scan_log("Scan failed: #{e.message}", kind: :error)
    render_scan_response(status: :unprocessable_entity)
  ensure
    params[:material] = "[FILTERED]" if params[:material].present?
    params[:private_keys] = "[FILTERED]" if params[:private_keys].present?
  end

  private

  def require_admin!
    return if current_user&.admin?

    redirect_to root_path, alert: "Admin access required."
  end

  def stream_name
    "utxo_scan_user_#{current_user.id}"
  end

  def node_rpc
    BitcoinRpc.new(
      url: ENV.fetch("BITCOIN_RPC_URL"),
      username: ENV.fetch("BITCOIN_RPC_USERNAME"),
      password: ENV.fetch("BITCOIN_RPC_PASSWORD"),
      wallet: nil
    )
  end

  # Replace log body with a real ERB partial (raw html: was escaping as text).
  def reset_scan_log!
    Turbo::StreamsChannel.broadcast_update_to(
      stream_name,
      target: "utxo_scan_log",
      partial: "shared/log_status",
      locals: { message: "Starting scan…" }
    )
  end

  def broadcast_scan_log(message, kind: :info)
    Turbo::StreamsChannel.broadcast_append_to(
      stream_name,
      target: "utxo_scan_log",
      partial: "wallets/log_line",
      locals: { message: message, kind: kind, at: Time.current }
    )
  end

  def broadcast_scan_table!
    Turbo::StreamsChannel.broadcast_replace_to(
      stream_name,
      target: "utxo_scan_results",
      partial: "utxo_scans/results",
      locals: { scan_result: @scan_result, build_errors: @build_errors }
    )
  end

  def run_scantxoutset_with_progress(client, descriptors)
    objs = Array(descriptors).uniq
    chunk_size = Integer(ENV.fetch("BITCOIN_RPC_SCANTXOUTSET_CHUNK", "50"))
    if objs.size <= chunk_size
      broadcast_scan_log("RPC scantxoutset start (#{objs.size} descriptors)…", kind: :info)
      return client.scantxoutset(objs)
    end

    merged = {
      "success" => true,
      "total_amount" => 0.0,
      "txouts" => 0,
      "height" => nil,
      "bestblock" => nil,
      "unspents" => []
    }
    chunks = objs.each_slice(chunk_size).to_a
    chunks.each_with_index do |chunk, i|
      broadcast_scan_log(
        "Chunk #{i + 1}/#{chunks.size}: scanning #{chunk.size} descriptors…",
        kind: :info
      )
      part = client.scantxoutset(chunk)
      next unless part.is_a?(Hash)

      merged["total_amount"] = merged["total_amount"].to_f + part["total_amount"].to_f
      merged["txouts"] = part["txouts"] if part["txouts"]
      merged["height"] = part["height"] if part["height"]
      merged["bestblock"] = part["bestblock"] if part["bestblock"]
      merged["unspents"].concat(Array(part["unspents"]))
      merged["success"] &&= part["success"] != false
      broadcast_scan_log(
        "Chunk #{i + 1}/#{chunks.size} done · partial total so far " \
        "#{merged["total_amount"]} BTC · UTXOs #{merged["unspents"].size}",
        kind: :ok
      )
    end
    # Dedup
    seen = {}
    merged["unspents"] = merged["unspents"].select do |u|
      key = "#{u["txid"]}:#{u["vout"]}"
      next false if seen[key]

      seen[key] = true
      true
    end
    merged["total_amount"] = merged["unspents"].sum { |u| u["amount"].to_f }
    merged
  end

  def render_scan_response(status: :ok)
    respond_to do |format|
      format.html { render :show, status: status }
      format.turbo_stream do
        streams = [
          turbo_stream.replace("utxo_scan_flash", partial: "utxo_scans/flash"),
          turbo_stream.replace(
            "utxo_scan_results",
            partial: "utxo_scans/results",
            locals: { scan_result: @scan_result, build_errors: @build_errors }
          )
        ]
        # Also re-append a final status line into the log via the response (in case Cable missed it)
        streams << turbo_stream.append(
          "utxo_scan_log",
          partial: "wallets/log_line",
          locals: {
            message: (@scan_result ? "Response complete — results table updated." : "Request finished."),
            kind: @scan_result ? :ok : :info,
            at: Time.current
          }
        )
        render turbo_stream: streams, status: status
      end
    end
  end

  def normalize_result(result, items:)
    result = {} unless result.is_a?(Hash)
    unspents = Array(result["unspents"]).map do |u|
      {
        txid: u["txid"],
        vout: u["vout"],
        amount: u["amount"].to_f,
        height: u["height"],
        script_pub_key: u["scriptPubKey"],
        desc: u["desc"].to_s
      }
    end

    # Group by human-readable label when possible
    by_display = Hash.new { |h, k| h[k] = { amount: 0.0, count: 0, descs: [] } }
    items_by_desc = items.index_by(&:descriptor)

    unspents.each do |u|
      # Core may return desc with checksum suffix: "addr(…)#…"
      bare = u[:desc].to_s.split("#", 2).first
      item = items_by_desc[bare] || items_by_desc[u[:desc]]
      label = item&.display || bare.presence || u[:desc].presence || "(unknown)"
      by_display[label][:amount] += u[:amount]
      by_display[label][:count] += 1
      by_display[label][:descs] << bare unless by_display[label][:descs].include?(bare)
    end

    totals = by_display.map do |label, v|
      { label: label, amount: v[:amount], count: v[:count], descs: v[:descs] }
    end.sort_by { |r| -r[:amount] }

    {
      success: result["success"],
      total_amount: result["total_amount"].to_f,
      txouts: result["txouts"],
      height: result["height"],
      bestblock: result["bestblock"],
      unspents: unspents,
      totals: totals,
      descriptor_count: items.size,
      scope: "scan-only"
    }
  end

  def detect_network
    chain = BitcoinRpc.from_env(wallet: nil).call("getblockchaininfo")["chain"]
    chain.presence || "main"
  rescue BitcoinRpc::Error
    "main"
  end

  def cast_bool(value, default:)
    return default if value.nil?

    ActiveModel::Type::Boolean.new.cast(value)
  end

  def format_errors(errors)
    return "" if errors.blank?

    errors.first(5).map { |e| "L#{e[:line]}: #{e[:message]}" }.join(" · ")
  end
end
