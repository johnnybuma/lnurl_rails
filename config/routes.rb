Rails.application.routes.draw do
  resources :chain_data

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"
  #


  devise_for :users, skip: [:registrations]
  as :user do
    get "/sign_in" => "devise/sessions#new" # custom path to login/sign_in
    get 'users/edit' => 'devise/registrations#edit', :as => 'edit_user_registration'
    put 'users' => 'devise/registrations#update', :as => 'user_registration'
  end
  #devise_for :users
  resources :users

  resources :block_histories

  get 'block_histories/:block_number/transactions', to: 'block_histories#show_transactions', as: 'block_transactions'

  get 'block_histories/transactions/:tx_id', to: 'block_histories#show_raw_transaction', as: 'block_history_transaction'


  root to: "chain_data#index"


  mount ActionCable.server => '/cable'

end
