class AnomaliesController < ApplicationController
  def index
    render json: [{id: 1, truck_id: 3, temperature: 9.1, anomaly: "HIGH TEMP 🚨"}]
  end
end
