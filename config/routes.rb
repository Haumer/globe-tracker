Rails.application.routes.draw do
  devise_for :users
  root to: "pages#home"
  get "sources", to: "pages#sources"

  get "admin", to: "admin#dashboard", as: :admin
  post "admin/toggle_poller", to: "admin#toggle_poller", as: :admin_toggle_poller
  post "admin/pause_poller", to: "admin#pause_poller", as: :admin_pause_poller
  post "admin/stop_poller", to: "admin#stop_poller", as: :admin_stop_poller

  namespace :api do
    resources :flights, only: [:index, :show]
    resources :satellites, only: [:index] do
      collection do
        get :search
      end
    end
    resources :ships, only: [:index]
    resources :webcams, only: [:index]
    resource :preferences, only: [:show, :update]
    resources :workspaces, only: [:index, :create, :update, :destroy]
    resources :watches, only: [:index, :create, :update, :destroy]
    resources :alerts, only: [:index, :update] do
      collection do
        post :mark_all_seen
      end
    end
    resource :connections, only: [:show]
    resources :anomalies, only: [:index]
    resource :area_report, only: [:show]
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
    resources :airports, only: [:index]
    resources :fire_hotspots, only: [:index]
    resources :playback, only: [:index] do
      collection do
        get :range
        get :events
        get :satellites
      end
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
