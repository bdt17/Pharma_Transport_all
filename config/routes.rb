Rails.application.routes.draw do
  get "drivers/dashboard"
  get "maps/index"
  # Health check route
  get "up" => "rails/health#show", as: :rails_health_check
  
  # Dashboard routes
  get "dashboard/index"
  root "dashboard#index"
  
  # API routes for GPS tracking (Phase 2)
  resources :vehicles, only: [:index, :create, :show] do
    member do
      post :update_location  # Real-time GPS updates
    end
  end
  
  resources :geofences, only: [:index, :create, :destroy]
  
  # ActionCable for live updates
  mount ActionCable.server => "/cable"
  
  # Driver portal routes (Phase 2 complete)
  namespace :drivers do
    get "dashboard"
    resources :checkins, only: [:create]
  end
  
  # Admin routes
  namespace :admin do
    resources :vehicles
    resources :geofences
    root to: "dashboard#index"
  end
end
