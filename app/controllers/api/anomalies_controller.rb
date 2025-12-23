class Api::AnomaliesController < ApplicationController
  def index
    render json: [{id: 1, truck: 3, temp: 9.1, anomaly: "HIGH TEMP 🚨", fixed: false}]
  end
end
