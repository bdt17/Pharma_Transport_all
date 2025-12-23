class SensorDataController < ApplicationController
  def index
    render json: SensorReading.last(3).presence || [{pharma:"TRUCK DATA 🚚 FDA"}]
  end
end
