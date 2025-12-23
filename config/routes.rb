Rails.application.routes.draw do
  root 'dashboard#index'
  
  get 'dashboard', to: 'dashboard#index'
  get 'pfizer', to: 'partners#pfizer'
  resources :sensors
  resources :partners
  
  # Add ALL your other routes HERE INSIDE this block
  # Add ALL your other routes HERE INSIDE this block
  post '/api/forecast/:vehicle_id', to: 'sensors#forecast'
  post '/api/tamper/:vehicle_id', to: 'sensors#tamper'
  get '/api/vision', to: 'sensors#vision'  # ← Simple route



  
end
