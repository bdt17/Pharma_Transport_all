Rails.application.routes.draw do
  # API ROUTES FIRST - Before React SPA catch-all
  post '/api/forecast/:vehicle_id', to: 'sensors#forecast'
  post '/api/tamper/:vehicle_id', to: 'sensors#tamper'
  get '/api/vision', to: 'sensors#vision'
  
  # React SPA routes AFTER APIs
  root 'dashboard#index'
  get 'dashboard', to: 'dashboard#index'
  get 'pfizer', to: 'partners#pfizer'
  resources :sensors
  resources :partners

get '/api/gps/:id', to: 'sensors#gps'           # Phase 14 GPS
get '/api/subscribe', to: 'sensors#subscribe'  # Phase 14 Stripe
get '/api/jetson', to: 'sensors#jetson'        # Phase 14 Vision

get '/api/compliance/audit', to: 'compliance#audit'
post '/api/compliance/sign', to: 'compliance#sign'


end
