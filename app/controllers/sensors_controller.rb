class SensorsController < ApplicationController
  def index
    render json: [{id:1,truck_id:1,temperature:4.2,"PHARMA":"TRUCK SENSORS 🚚 FDA"}]
  end

  def forecast
    result = SensorReading.forecast_demand(params[:vehicle_id])
    render json: { forecast: result, status: 'success' }
  end

  def tamper
    vehicle = Vehicle.find(params[:vehicle_id])
    result = vehicle.detect_tamper(params[:vibration].to_f, params[:light].to_f)
    render json: result, status: :ok
  end
end
