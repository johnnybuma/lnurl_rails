require File.expand_path('../config/environment', __FILE__)
require 'bitcoin_core_rpc'
include ActionView::Helpers

rpc_url = ENV['BITCOIN_RPC_URL']
rpc_user = ENV['BITCOIN_RPC_USERNAME']
rpc_password = ENV['BITCOIN_RPC_PASSWORD']

bitcoin = BitcoinCoreRpc::API.new(rpc_url, rpc_user, rpc_password)

while true
  @chain_data = bitcoin.get_blockchain_info["result"]
  @block_count = bitcoin.get_block_count

  @chain_data.each do |key, value|
    # Convert value to a suitable string format if it is a complex object
    value = value.to_json if value.is_a?(Hash) || value.is_a?(Array)

    # Create a new record for each key-value pair
    ChainDatum.create(key: key, value: value)
  end

  ActionCable.server.broadcast('chain_data_channel', @chain_data)

  puts @chain_data
  puts "Waiting 10 seconds for next update"

  sleep 10
end
