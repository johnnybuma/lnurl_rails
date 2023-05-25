class UpdateChainDataJob < ApplicationJob
  queue_as :default

  require 'bitcoin_core_rpc'


  def perform
    rpc_url = ENV['BITCOIN_RPC_URL']
    rpc_user = ENV['BITCOIN_RPC_USERNAME']
    rpc_password = ENV['BITCOIN_RPC_PASSWORD']

    bitcoin = BitcoinCoreRpc::API.new(rpc_url, rpc_user, rpc_password)

    @chain_data = bitcoin.get_blockchain_info["result"].to_a

    ActionCable.server.broadcast'chain_data_channel', @chain_data

  end
end
