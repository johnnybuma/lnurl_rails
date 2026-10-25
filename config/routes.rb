Rails.application.routes.draw do
  resources :chain_data

  devise_for :users, skip: [:registrations]
  as :user do
    get "/sign_in" => "devise/sessions#new"
    get "users/edit" => "devise/registrations#edit", as: "edit_user_registration"
    put "users" => "devise/registrations#update", as: "user_registration"
  end
  resources :users

  # Query-param friendly lookups for Chart View (before resources)
  get "explorer/block_transactions", to: "block_histories#show_transactions", as: :lookup_block_transactions
  get "explorer/raw_transaction", to: "block_histories#show_raw_transaction", as: :lookup_raw_transaction

  get "block_histories/transactions/:tx_id", to: "block_histories#show_raw_transaction", as: "block_history_transaction"
  get "block_histories/:block_number/transactions", to: "block_histories#show_transactions", as: "block_transactions"

  resources :block_histories

  # Multi-wallet: index lists all; each wallet has its own show + RPC actions
  resources :wallets, only: %i[index show create], constraints: { id: /[^\/]+/ } do
    collection do
      # Batch import: auto-creates nodeviewWallet01, 02, … — no name/label fields
      post :batch_import
      # scantxoutset for every known wallet → Postgres (no chain rescan, no import)
      post :rescan_all_utxos
      # Re-fill script addresses for every wallet’s stored private-key pubkeys
      post :refill_all_private_keys
    end
    member do
      post :load
      post :unload
      post :refresh
      post :import_key
      post :import_keys
      post :import_pubkeys
      post :scan_utxos
      post :scan_imported_keys
      post :scan_watch_only
      post :abort_rescan
      # Re-derive + import full HD gap (20 receive + 20 change per stored xpub/zpub)
      post :load_all_addresses
      # Re-fill p2pkh/p2wpkh/p2sh-p2wpkh from stored private-key pubkeys + UTXO scan
      post :refill_private_keys
    end
  end

  # Legacy singular path → multi-wallet index
  get "/wallet", to: redirect("/wallets")

  # Scan-only: scantxoutset with no wallet import and no Postgres writes
  resource :utxo_scan, only: %i[show create], controller: "utxo_scans"

  root to: "chain_data#index"

  mount ActionCable.server => "/cable"
end
