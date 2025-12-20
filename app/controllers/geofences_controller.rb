class GeofencesController < ApplicationController
  def index
    @geofences = Geofence.all
    render json: @geofences
  end

  def create
    @geofence = Geofence.create!(geofence_params)
    render json: @geofence, status: :created
  end

  private
  def geofence_params
    params.require(:geofence).permit(:name, :latitude, :longitude, :radius)
  end
end
