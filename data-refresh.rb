require File.expand_path('../config/environment', __FILE__)
require 'bitcoin_core_rpc'
include ActionView::Helpers

rpc_url = "http://localhost:8332"
rpc_user = "bitcoin"
rpc_password = "hotrod212"

bitcoin = BitcoinCoreRpc::API.new(rpc_url, rpc_user, rpc_password)


while true

  @chain_data = bitcoin.get_blockchain_info["result"]

  @block_count = bitcoin.get_block_count


  #@view_data = ChainDataController.renderer.render(partial: 'chain_data/chain_data')
  #@send_data = {chain_data: @chain_data, target: 'chain_data'}

  ActionCable.server.broadcast('chain_data_channel', @chain_data)

  puts @chain_data
  puts "Waiting 10 seconds for next update"

  sleep 10

end


