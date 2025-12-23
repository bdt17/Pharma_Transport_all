class SensorDataController < ApplicationController
  def index
    render json: [{"PHARMA":"SENSOR DATA LIVE 🚚","truck_id":1,"fda":"21 CFR 11"}]
  end
end
