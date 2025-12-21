Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      get "realtime/index"
    end
  end
  root "dashboard#index"
  get '/dashboard', to: 'dashboard#index'
  get '/vehicles', to: 'dashboard#index'
  get '/map', to: 'dashboard#index'
  get '/vehicles/1/map', to: 'dashboard#index'
  get '/audit_events', to: 'dashboard#index'
  get '/geofences', to: 'dashboard#index'
  get '/sensor_readings', to: 'dashboard#index'
  get '/electronic_signatures', to: 'dashboard#index'
  get '/dea_shipments', to: 'dashboard#index'
  get '/transport_anomalies', to: 'dashboard#index'
end
