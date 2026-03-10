Rails.application.routes.draw do
  devise_for :users
  root to: "pages#home"

  namespace :api do
    resources :flights, only: [:index, :show]
    resources :satellites, only: [:index]
    resources :ships, only: [:index]
    resources :webcams, only: [:index]
    resource :preferences, only: [:show, :update]
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
