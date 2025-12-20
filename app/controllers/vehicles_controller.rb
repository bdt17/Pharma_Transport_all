class VehiclesController < ApplicationController
  def index
    @vehicles = Vehicle.all
    render json: @vehicles
  end

  def update_gps
    Vehicle.all.each do |v|
      v.update_columns(
        latitude: [[v.latitude + rand(-0.001..0.001), 33.3, 36.3].min, 33.3].max,
        longitude: [[v.longitude + rand(-0.001..0.001), -115.5, -111.5].min, -115.5].max
      )
    end
    render json: Vehicle.all
  end
end
