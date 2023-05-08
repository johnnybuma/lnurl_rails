class UpdateBitcoinDataJob < ApplicationJob
  queue_as :default

  require 'bitcoin_core_rpc'
  include ActionView::RecordIdentifier


  def perform
    rpc_url = "http://192.168.1.26:8332"
    rpc_user = "bitcoin"
    rpc_password = "hotrod212"

    bitcoin = BitcoinCoreRpc::API.new(rpc_url, rpc_user, rpc_password)

    @blockchain_info = bitcoin.get_blockchain_info["result"].to_a

    ActionCable.server.broadcast'bitcoin_data', @blockchain_info

  end
end
