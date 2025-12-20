Rails.application.routes.draw do
  root 'home#landing'
  
  # Dashboard at /dashboard
  get '/dashboard', to: 'dashboard#index'
end
