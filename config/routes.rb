Rails.application.routes.draw do
  get "vehicles/index"
  get "up" => "rails/health#show", as: :rails_health_check
get '/api/vehicles', to: 'vehicles#index'
  root "dashboard#index"

  # DRIVER ROUTES - COMPLETE
  get '/drivers/sign_up', to: 'drivers#new'
  post '/drivers', to: 'drivers#create'
  get '/drivers/dashboard', to: 'drivers#dashboard', as: :drivers_dashboard
  post '/drivers/checkin', to: 'drivers#checkin', as: :drivers_checkin
end
root 'admin#index'
get '/admin', to: 'admin#index'
namespace :api do
  post '/locations', to: 'locations#create'
end
mount ActionCable.server => '/cable'
