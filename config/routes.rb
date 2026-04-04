Rails.application.routes.draw do
  devise_for :users
  root to: "pages#home"
  get "home", to: "pages#landing", as: :landing
  get "sources", to: "pages#sources"
  get "about", to: "pages#about"
  get "objects/:kind/:id", to: "objects#show", as: :object_view
  resources :areas, controller: "area_workspaces", only: [:index, :show, :create]
  resources :cases, controller: "investigation_cases", only: [:index, :show, :new, :create, :update] do
    resources :notes, controller: "investigation_case_notes", only: [:create]
  end
  resources :case_objects, controller: "investigation_case_objects", only: [:create]

  get "admin", to: "admin#dashboard", as: :admin
  get "admin/api_health", to: "admin#api_health", as: :admin_api_health
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
    resources :ports, only: [:index]
    resources :shipping_lanes, only: [:index]
    resources :pipelines, only: [:index]
    resources :railways, only: [:index]
    resources :trains, only: [:index]
    resources :internet_outages, only: [:index]
    resources :power_plants, only: [:index]
    resources :conflict_events, only: [:index]
    get "conflict_pulse", to: "conflict_pulse#index"
    get "chokepoints", to: "chokepoints#index"
    resources :internet_traffic, only: [:index]
    resources :notams, only: [:index]
    resources :airports, only: [:index]
    resources :trending, only: [:index]
    resources :fire_hotspots, only: [:index]
    resources :strikes, only: [:index]
    resources :weather_alerts, only: [:index]
    resources :insights, only: [:index]
    get "node_context", to: "node_contexts#show"
    resources :military_bases, only: [:index]
    resources :commodities, only: [:index]
    resource :brief, only: [:show]
    resource :exports, only: [] do
      get :geojson
      get :csv
      get "flight_history/:id", action: :flight_history, as: :flight_history
    end
    resources :playback, only: [:index] do
      collection do
        get :range
        get :events
        get :satellites
        get :conflicts
      end
    end
  end

  get "health" => "health#show"
  get "version" => "version#show"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
