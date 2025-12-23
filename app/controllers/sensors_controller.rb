class SensorsController < ApplicationController
  def index
    # Your existing sensor model (from Phase 6)
    sensors = SensorReading.last(10) || []
    render json: sensors.map { |s| { 
      id: s.id, 
      truck_id: s.truck_id, 
      temperature: s.temperature,
      timestamp: s.created_at 
    }}
  end
end
