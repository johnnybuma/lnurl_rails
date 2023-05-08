class HomeController < ApplicationController

  require 'bitcoin_core_rpc'



  def index

    rpc_url = "http://192.168.1.26:8332"
    rpc_user = "bitcoin"
    rpc_password = "hotrod212"

    bitcoin = BitcoinCoreRpc::API.new(rpc_url, rpc_user, rpc_password)

    @blockchain_info = bitcoin.get_blockchain_info["result"].to_a





    @block_count = bitcoin.get_block_count

    UpdateBitcoinDataJob.perform_now

    ActionCable.server.broadcast "bitcoin_data_channel", @blockchain_info



  end



end
