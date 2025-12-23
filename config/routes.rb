Rails.application.routes.draw do
  root 'dashboard#index'
  
  get 'dashboard', to: 'dashboard#index'
  get 'pfizer', to: 'partners#pfizer'
  resources :sensors
  resources :partners
  
  # Add ALL your other routes HERE INSIDE this block
  
end
