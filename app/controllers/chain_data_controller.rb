class ChainDataController < ApplicationController
  before_action :set_chain_datum, only: %i[ show edit update destroy ]

  require 'bitcoin_core_rpc'


  # GET /chain_data or /chain_data.json
  def index

    rpc_url = "http://192.168.1.26:8332"
    rpc_user = "bitcoin"
    rpc_password = "hotrod212"

    bitcoin = BitcoinCoreRpc::API.new(rpc_url, rpc_user, rpc_password)

    @chain_data = bitcoin.get_blockchain_info["result"]

    @block_count = bitcoin.get_block_count

    ActionCable.server.broadcast 'chain_data_channel', @chain_data


  end

  # GET /chain_data/1 or /chain_data/1.json
  def show
  end

  # GET /chain_data/new
  def new
    @chain_datum = ChainDatum.new
  end

  # GET /chain_data/1/edit
  def edit
  end

  # POST /chain_data or /chain_data.json
  def create
    @chain_datum = ChainDatum.new(chain_datum_params)

    respond_to do |format|
      if @chain_datum.save
        format.html { redirect_to chain_datum_url(@chain_datum), notice: "Chain datum was successfully created." }
        format.json { render :show, status: :created, location: @chain_datum }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @chain_datum.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /chain_data/1 or /chain_data/1.json
  def update
    respond_to do |format|
      if @chain_datum.update(chain_datum_params)
        format.html { redirect_to chain_datum_url(@chain_datum), notice: "Chain datum was successfully updated." }
        format.json { render :show, status: :ok, location: @chain_datum }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @chain_datum.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /chain_data/1 or /chain_data/1.json
  def destroy
    @chain_datum.destroy

    respond_to do |format|
      format.html { redirect_to chain_data_url, notice: "Chain datum was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_chain_datum
      @chain_datum = ChainDatum.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def chain_datum_params
      params.fetch(:chain_datum, {})
    end
end
