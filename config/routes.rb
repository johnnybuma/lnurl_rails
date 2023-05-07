Rails.application.routes.draw do
  resources :rooms do
    resources :messages
  end
  
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"
  #


  devise_scope :user do
    # Redirests signing out users back to sign-in
    get "users", to: "devise/sessions#new"
  end
  #devise_for :users
  resources :users

  root to: "home#index"


  mount ActionCable.server => '/cable'

end
