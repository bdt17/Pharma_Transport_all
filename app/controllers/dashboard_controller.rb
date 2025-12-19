class DashboardController < ApplicationController
  def index
    @vehicles = Vehicle.all.order(:name)
    @geofences = Geofence.all
  end
end
