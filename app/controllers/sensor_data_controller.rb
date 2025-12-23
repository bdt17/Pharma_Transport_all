class SensorDataController < ApplicationController
  def index
    render json: SensorReading.last(5)
  end
end
