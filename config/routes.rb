Rails.application.routes.draw do
  devise_for :users
  root to: "pages#home"
  get "sources", to: "pages#sources"

  namespace :api do
    resources :flights, only: [:index, :show]
    resources :satellites, only: [:index]
    resources :ships, only: [:index]
    resources :webcams, only: [:index]
    resource :preferences, only: [:show, :update]
    resources :news, only: [:index]
    resources :earthquakes, only: [:index]
    resources :natural_events, only: [:index]
    resources :gps_jamming, only: [:index]
    resources :submarine_cables, only: [:index]
    resources :internet_outages, only: [:index]
    resources :power_plants, only: [:index]
    resources :conflict_events, only: [:index]
    resources :internet_traffic, only: [:index]
    resources :notams, only: [:index]
    resources :playback, only: [:index] do
      collection do
        get :range
        get :events
      end
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
