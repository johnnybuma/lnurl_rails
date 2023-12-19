# app/controllers/block_histories_controller.rb
class BlockHistoriesController < ApplicationController
  def index
    start_block = params[:start_block] || BlockHistory.minimum(:block_number)
    end_block = params[:end_block] || BlockHistory.maximum(:block_number)

    block_histories = BlockHistory.where(block_number: start_block..end_block)

    @chart_data = block_histories.map do |block_history|
      begin
        data = JSON.parse(block_history.data)
        {
          block_number: block_history.block_number,
          difficulty: data['result']['difficulty'].to_f,  # Assumes 'difficulty' is a top-level key
          chainwork: data['result']['chainwork'].to_f     # Assumes 'chainwork' is a top-level key
        }
      rescue JSON::ParserError, TypeError
        # Handle JSON parsing errors or return a default structure
        { block_number: block_history.block_number, difficulty: nil, chainwork: nil }
      end
    end
  end
end
