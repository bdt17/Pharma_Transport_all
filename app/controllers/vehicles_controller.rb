class VehiclesController < ApplicationController
  def index
    @vehicles = Vehicle.all
  end

  def map
    @vehicles = Vehicle.all
  end

  def update_gps
    Vehicle.find_each do |v|
      v.update_columns(
        last_lat: [v.last_lat || 33.4484 + rand(-0.001..0.001), 33.3].max,
        last_lng: [v.last_lng || -112.0740 + rand(-0.001..0.001), -115.5].min
      )
    end
    redirect_to map_path, notice: "GPS updated!"
  end
end
