class VehiclesController < ApplicationController
def update_gps
  Vehicle.all.each do |v|
    v.update!(
      latitude: v.latitude + rand(-0.001..0.001),
      longitude: v.longitude + rand(-0.001..0.001)
    )
  end
  render json: Vehicle.all
end


end

  def index
    render json: Vehicle.all
  end

  def index
    render json: Vehicle.all
  end

  def index
    render json: Vehicle.all
  end

  def update_gps
    Vehicle.all.each do |v|
      v.update!(
        latitude: v.latitude + rand(-0.001..0.001),
        longitude: v.longitude + rand(-0.001..0.001)
      )
    end
    render json: Vehicle.all
  end
