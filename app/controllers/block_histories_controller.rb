# app/controllers/block_histories_controller.rb
class BlockHistoriesController < ApplicationController
  require "bitcoin_core_rpc"

  # Hard caps so Chart View never scans / materializes the full archive.
  MAX_CHART_BLOCKS = 1_000
  DEFAULT_CHART_BLOCKS = 200

  def index
    @db_max = BlockHistory.maximum(:block_number)
    @db_min = BlockHistory.minimum(:block_number)
    @db_count = BlockHistory.count

    @start_block, @end_block, @chart_capped, @chart_message = resolve_chart_range
    @chart_data = load_chart_data(@start_block, @end_block)

    @chain_datum = ChainDatum.new
    @chain_data_records = ChainDatum.order(updated_at: :desc).limit(25)

    respond_to do |format|
      format.html
      format.json { render json: @chart_data }
    end
  end

  def show_transactions
    block_number = params[:block_number]
    @block = BlockHistory.find_by(block_number: block_number)
    @transactions = if @block
                      JSON.parse(@block.data).dig("result", "tx") || []
                    else
                      []
                    end
    @block_number = block_number
    @missing_block = @block.nil? && block_number.present?

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def show_raw_transaction
    tx_id = params[:tx_id].to_s.strip
    @tx_id = tx_id
    @transaction = {}
    @rpc_error = nil

    if tx_id.blank?
      @rpc_error = "Enter a transaction id."
    else
      begin
        bitcoin = bitcoin_rpc
        raw_tx = bitcoin.get_raw_transaction(tx_id)
        if raw_tx.is_a?(Hash) && raw_tx.key?("result") && raw_tx["result"]
          @transaction = raw_tx["result"]
        elsif raw_tx.is_a?(Hash) && raw_tx["error"]
          @rpc_error = raw_tx["error"]["message"] || raw_tx["error"].to_s
        else
          @rpc_error = "Unexpected RPC response for transaction."
        end
      rescue StandardError => e
        @rpc_error = e.message
      end
    end

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  private

  def resolve_chart_range
    # Explicit range from form / query
    if params[:start_block].present? || params[:end_block].present?
      start_block = params[:start_block].presence&.to_i
      end_block = params[:end_block].presence&.to_i

      start_block = @db_min || 0 if start_block.nil?
      end_block = @db_max || start_block if end_block.nil?

      start_block, end_block = end_block, start_block if start_block > end_block

      span = end_block - start_block + 1
      capped = false
      message = nil

      if span > MAX_CHART_BLOCKS
        # Keep the end of the requested window (most recent in range)
        start_block = end_block - MAX_CHART_BLOCKS + 1
        capped = true
        message = "Range capped to #{MAX_CHART_BLOCKS} blocks (#{start_block}–#{end_block}). Full archive is not loaded into the chart."
      end

      return [start_block, end_block, capped, message]
    end

    # Default: only the latest DEFAULT_CHART_BLOCKS rows by height — never 0..tip
    if @db_max.nil?
      return [0, 0, false, "No block_histories rows yet. Chart stays empty until data exists."]
    end

    start_block = [@db_max - DEFAULT_CHART_BLOCKS + 1, @db_min || 0].max
    end_block = @db_max
    message = "Showing latest #{end_block - start_block + 1} blocks (#{start_block}–#{end_block}). Pick a range ≤ #{MAX_CHART_BLOCKS} blocks to chart."
    [start_block, end_block, false, message]
  end

  # Pull only chart scalars via SQL JSON extract — never instantiate AR with full `data` blobs.
  def load_chart_data(start_block, end_block)
    return [] if start_block.nil? || end_block.nil?
    return [] if @db_max.nil?

    sql = <<~SQL
      SELECT block_number,
             COALESCE((data::json->'result'->>'difficulty')::double precision, 0) AS difficulty,
             COALESCE((data::json->'result'->>'nTx')::double precision, 0) AS n_tx,
             COALESCE((data::json->'result'->>'size')::double precision, 0) / 1048576.0 AS size_mb
      FROM block_histories
      WHERE block_number BETWEEN $1 AND $2
      ORDER BY block_number ASC
      LIMIT $3
    SQL

    binds = [
      ActiveRecord::Relation::QueryAttribute.new("start", start_block, ActiveRecord::Type::Integer.new),
      ActiveRecord::Relation::QueryAttribute.new("end", end_block, ActiveRecord::Type::Integer.new),
      ActiveRecord::Relation::QueryAttribute.new("lim", MAX_CHART_BLOCKS, ActiveRecord::Type::Integer.new)
    ]

    rows = ActiveRecord::Base.connection.exec_query(sql, "chart_data", binds)
    rows.map do |row|
      [
        row["block_number"].to_i,
        row["difficulty"].to_f,
        row["n_tx"].to_f,
        row["size_mb"].to_f
      ]
    end
  rescue StandardError => e
    Rails.logger.error("[BlockHistories#index] chart load failed: #{e.class}: #{e.message}")
    @chart_message = "Chart query failed: #{e.message}"
    []
  end

  def bitcoin_rpc
    BitcoinCoreRpc::API.new(
      ENV.fetch("BITCOIN_RPC_URL"),
      ENV.fetch("BITCOIN_RPC_USERNAME"),
      ENV.fetch("BITCOIN_RPC_PASSWORD")
    )
  end
end
