Rails.application.routes.draw do
  root 'home#landing'
  get '/dashboard', to: 'dashboard#index'
  get '/landing', to: 'home#landing'
  resources :vehicles
  resources :geofences
end
