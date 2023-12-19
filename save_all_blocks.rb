require File.expand_path('../config/environment', __FILE__)
require 'bitcoin_core_rpc'
require 'json'


rpc_url = ENV['BITCOIN_RPC_URL']
rpc_user = ENV['BITCOIN_RPC_USERNAME']
rpc_password = ENV['BITCOIN_RPC_PASSWORD']

bitcoin = BitcoinCoreRpc::API.new(rpc_url, rpc_user, rpc_password)

# Fetch the current block count
block_count_response = bitcoin.get_block_count
current_block_count = block_count_response.is_a?(Hash) ? block_count_response["result"] : block_count_response

# Replace this with the block number you want to start from
start_block = 0

if start_block > current_block_count
  puts "Start block number (#{start_block}) is greater than the current block count (#{current_block_count}). Exiting."
  exit
end

cumulative_data_size = 0

(start_block..current_block_count).each do |block_number|
  block_hash = bitcoin.get_block_hash(block_number)
  block_data = bitcoin.get_block(block_hash["result"].to_s)
  block_data_json = block_data.to_json

  # Calculate the size of the current block data in bytes
  current_data_size = block_data_json.bytesize
  cumulative_data_size += current_data_size

  # Save block data to the BlockHistory model
  BlockHistory.create(
    block_number: block_number,
    block_hash: block_hash["result"].to_s,
    data: block_data_json
  )

  # Calculate and display the progress percentage
  progress_percentage = ((block_number - start_block + 1).to_f / (current_block_count - start_block + 1) * 100).round(2)
  puts "Progress: #{progress_percentage}% (Block #{block_number} of #{current_block_count})"

  # Display the cumulative data size in a human-readable format
  puts "Cumulative data size stored: #{cumulative_data_size / 1024.0 / 1024.0} MB"
end

puts "Completed saving all blocks up to #{current_block_count}"
