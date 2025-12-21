Rails.application.routes.draw do
  get "audit_events/index"
  root 'home#landing'
  get '/dashboard', to: 'dashboard#index'
  get '/pricing', to: 'dashboard#pricing'

mount ActionCable.server => '/cable'


  # DRIVERS ROUTES
  get '/drivers/sign_up', to: 'drivers/registrations#new'
  namespace :drivers do
    resources :dashboard, only: [:show]
  end

  # GPS MAP + LIVE TRACKING (FIXED)
  get '/map', to: 'vehicles#map', as: :map # NEW: /map
  resources :vehicles, only: [:index] do
    member do
      get :map  # /vehicles/:id/map
    end
  end

  # GPS API (JSON only)
  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      resources :vehicles, only: [] do
        post :telemetries, controller: 'vehicle_telemetries'
      end
      resources :sensor_readings, only: :create
    end
  end

  # FDA COMPLIANCE
  resources :audit_events, only: [:index]
  resources :geofences, only: [:index, :new, :create]

  # Devise (AFTER User model exists)
  devise_for :users, controllers: { registrations: 'registrations' }
  devise_for :drivers
end
