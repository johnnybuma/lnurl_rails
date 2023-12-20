# app/controllers/block_histories_controller.rb
class BlockHistoriesController < ApplicationController
  def index
    start_block = params[:start_block].to_i
    end_block = params[:end_block].to_i

    range = [end_block - start_block, 1].max
    data_points = 1000 # This is the number of points you want to plot.
    interval = [1, (range.to_f / data_points).ceil].max

    @block_histories = BlockHistory
                         .where(block_number: start_block..end_block)
                         .where('block_number % ? = 0', interval)
                         .order(:block_number)

    @chart_data = @block_histories.pluck(:block_number, :data).map do |block_number, data_json|
      data = JSON.parse(data_json)
      response = data['result'] || {}
      difficulty = response['difficulty'] || 0
      chainwork = response['chainwork'] || 0
      [block_number, difficulty.to_f, chainwork.to_f]
    end
  end
end
