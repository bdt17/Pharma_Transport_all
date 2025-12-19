class VehiclesController < ApplicationController
  def index
    vehicles = [
      {id: 1, name: "F-150", lat: 33.44, lng: -112.07, status: "Phoenix → Tucson"},
      {id: 2, name: "Transit", lat: 32.22, lng: -110.97, status: "Tucson → Hospital"},
      {id: 3, name: "Box Truck", lat: 33.45, lng: -112.06, status: "Local delivery"}
    ]
    render json: vehicles
  end
end
