# app/controllers/block_histories_controller.rb
class BlockHistoriesController < ApplicationController
  BATCH_SIZE = 50000 # Adjust the batch size based on your performance tests

  def index
    start_block = params[:start_block].to_i
    end_block = params[:end_block].to_i
    batch_number = params[:batch_number].to_i || 0

    offset = batch_number * BATCH_SIZE
    @block_histories = BlockHistory
                         .where(block_number: start_block..end_block)
                         .order(:block_number)
                         .offset(offset)
                         .limit(BATCH_SIZE)

    # Initialize an empty array for chart data
    chart_data = []

    # Populate chart_data with only the necessary values
    @block_histories.each do |block_history|
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
end
