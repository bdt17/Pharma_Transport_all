Rails.application.routes.draw do
  get "health/up"
  get "health/status"
  get "partners/pfizer"
  get "subscriptions/new"
  get "subscriptions/create"
  root "dashboard#index"
  get "dashboard", to: "dashboard#index"
  get "api/v1/realtime", to: "api/v1/realtime#index"
  get "electronic_signatures", to: "electronic_signatures#index"
  get "dea_shipments", to: "dea_shipments#index"
  get "transport_anomalies", to: "transport_anomalies#index"
  get "billing", to: "billing#index"
 
 # ALL your routes INSIDE here:
  get 'pfizer', to: 'partners#pfizer'  # Line 22 ← MOVE INSIDE
  get 'dashboard', to: 'dashboard#index'
  resources :sensors
  # ... all other routes ...

  
  # Stripe Billing - Phase 8 Revenue
  resources :subscriptions, only: [:new, :create]
  get 'upgrade', to: 'subscriptions#new'
  get '/api/sensors', to: 'sensors#index'
end


get 'pfizer', to: 'partners#pfizer'

namespace :api do
  get '/sensors', to: 'sensors#index'
  get '/anomalies', to: 'anomalies#index'
  get '/sensor_data', to: 'sensor_data#index'
end

# Phase 10 CERT APIs
get '/api/sensors', to: 'sensors#index'
get '/api/anomalies', to: 'anomalies#index'
get '/api/sensor_data', to: 'sensor_data#index'

get '/api/sensors', to: 'sensors#index'
get '/api/anomalies', to: 'anomalies#index'
get '/api/sensor_data', to: 'sensor_data#index'

# FDA SECURITY - Block sensitive files
match '/.env' => 'errors#not_found', via: :all
match '/config/*' => 'errors#not_found', via: :all
match '/*secret*' => 'errors#not_found', via: :all

# FDA SECURITY - Block BEFORE React SPA
match '/.env' => proc { [404, {}, ['']] }, via: :all
match '/config/*' => proc { [404, {}, ['']] }, via: :all
match '/*.(key|env|yml)' => proc { [404, {}, ['']] }, via: :all
get '/api/sensors', to: 'sensors#index'
get '/api/anomalies', to: 'anomalies#index'
get '/api/sensor_data', to: 'sensor_data#index'
post '/webhooks/pfizer', to: 'webhooks#receive'
get '/api/sensors', to: 'sensors#index'
get '/api/anomalies', to: 'anomalies#index'
get '/api/sensor_data', to: 'sensor_data#index'
