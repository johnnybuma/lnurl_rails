class UpdateBitcoinDataJob < ApplicationJob
  queue_as :default

  require 'bitcoin_core_rpc'
  include ActionView::RecordIdentifier


  def perform
    rpc_url = ENV['BITCOIN_RPC_URL']
    rpc_user = ENV['BITCOIN_RPC_USERNAME']
    rpc_password = ENV['BITCOIN_RPC_PASSWORD']

    bitcoin = BitcoinCoreRpc::API.new(rpc_url, rpc_user, rpc_password)

    @blockchain_info = bitcoin.get_blockchain_info["result"].to_a

    ActionCable.server.broadcast'bitcoin_data', @blockchain_info

  end
end
