class VehiclesController < ApplicationController
  respond_to :json

  def index
    @vehicles = Vehicle.all
    respond_with @vehicles
  end

  def update_gps
    Vehicle.all.each do |v|
      v.update_columns(
        latitude: [v.latitude + rand(-0.001..0.001), 33.3, 36.3].clamp(33.3, 36.3),
        longitude: [v.longitude + rand(-0.001..0.001), -115.5, -111.5].clamp(-115.5, -111.5)
      )
    end
    respond_with Vehicle.all
  end
end

  def update_gps
    Vehicle.all.each do |v|
      v.update_columns(
        latitude: [v.latitude + rand(-0.001..0.001), 33.3, 36.3].clamp(33.3, 36.3),
        longitude: [v.longitude + rand(-0.001..0.001), -115.5, -111.5].clamp(-115.5, -111.5)
      )
    end
    render json: Vehicle.all
  end

  def update_gps
    Vehicle.all.each do |v|
      v.update_columns(
        latitude: [v.latitude + rand(-0.001..0.001), 33.3, 36.3].clamp(33.3, 36.3),
        longitude: [v.longitude + rand(-0.001..0.001), -115.5, -111.5].clamp(-115.5, -111.5)
      )
    end
    render json: Vehicle.all
  end
