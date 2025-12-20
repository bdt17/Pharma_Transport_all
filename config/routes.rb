Rails.application.routes.draw do
  root "admin#index"
  
  get "/vehicles", to: "vehicles#index"
  get "/vehicles/update_gps", to: "vehicles#update_gps"
  
  resources :vehicles
end
