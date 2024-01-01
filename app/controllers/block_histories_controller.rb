# app/controllers/block_histories_controller.rb
class BlockHistoriesController < ApplicationController


  BATCH_SIZE = 20000 # Adjust the batch size based on your performance tests

  def index
    start_block = params[:start_block].to_i
    end_block = params[:end_block].to_i
    batch_number = params[:batch_number].to_i || 0

    offset = batch_number * BATCH_SIZE

    # Initialize an empty array for chart data
    chart_data = []

    # Select only needed columns and use find_each for batch processing
    BlockHistory
      .select(:id, :block_number, :data)
      .where(block_number: start_block..end_block)
      .order(:block_number)
      .offset(offset)
      .limit(BATCH_SIZE)
      .find_each(batch_size: BATCH_SIZE) do |block_history| # Adjust batch_size as needed



      data = JSON.parse(block_history.data)
      response = data['result'] || {}

      # Extract difficulty and number of transactions
      difficulty = response['difficulty'] || 0
      numtxs = response['nTx'] || 0
      blocksize = response["size"] / 1.0.megabyte

      # Push the required data into the chart_data array
      chart_data << [block_history.block_number, difficulty.to_f, numtxs.to_f, blocksize.to_f]
    end

    # Assign the prepared data to @chart_data for use in the view
    @chart_data = chart_data



    respond_to do |format|
      format.html # for the initial page load
      format.json { render json: @chart_data } # for AJAX requests
    end
  end

  def show_transactions
    @block = BlockHistory.find_by(block_number: params[:block_number])
    @transactions = @block ? JSON.parse(@block.data).dig('result', 'tx') || [] : []

  end


  def show_raw_transaction

    tx_id = params[:tx_id]


    rpc_url = ENV['BITCOIN_RPC_URL']
    rpc_user = ENV['BITCOIN_RPC_USERNAME']
    rpc_password = ENV['BITCOIN_RPC_PASSWORD']

    bitcoin = BitcoinCoreRpc::API.new(rpc_url, rpc_user, rpc_password)

    raw_tx = bitcoin.get_raw_transaction(tx_id)

    # Check if raw_tx is already a Hash and contains the needed data
    if raw_tx.is_a?(Hash) && raw_tx.key?('result')
      @transaction = raw_tx['result']
    else
      # Handle the case where raw_tx is not in the expected format
      @transaction = {} # or handle this case as needed
    end



  end




end
