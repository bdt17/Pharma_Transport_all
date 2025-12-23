class AnomaliesController < ApplicationController
  def index
    render json: [{id:1,truck:3,temp:9.1,"anomaly":"FDA HIGH TEMP 🚨 PHARMA"}]
  end
end
