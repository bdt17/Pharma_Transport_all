Rails.application.routes.draw do
  get "pricing/index"
  root 'home#landing'
  get '/dashboard', to: 'dashboard#index'
  get '/landing', to: 'home#landing'
  
  # DRIVERS ROUTES (Fix Add Driver button)
  get '/drivers/sign_up', to: 'drivers#new'
  resources :drivers
  
  resources :vehicles
  resources :geofences
end
get '/pricing', to: 'pricing#index'
get '/pricing', to: 'pricing#index'

# Pricing page
get '/pricing', to: 'pricing#index'

# Pricing page
get '/pricing', to: 'pricing#index'
