class AnomaliesController < ApplicationController
  def index
    render json: [{id:1,truck_id:3,temp:9.1,anomaly:"FDA ALERT 🚨 PHARMA"}]
  end
end
