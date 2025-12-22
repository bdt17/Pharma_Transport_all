Rails.application.routes.draw do
  root "dashboard#index"
  get "dashboard", to: "dashboard#index"
  get "api/v1/realtime", to: "api/v1/realtime#index"
  get "electronic_signatures", to: "electronic_signatures#index"
  get "dea_shipments", to: "dea_shipments#index"
  get "transport_anomalies", to: "transport_anomalies#index"
  get "billing", to: "billing#index"
end
