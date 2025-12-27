class TrackingsController < ApplicationController
  def index
    # Your pharma GPS data (check_pharma.sh output)
    shipments = [
      {id: 1, status: "In Transit", lat: 33.4484, lng: -112.0740, temp: "2-8°C"},
      {id: 2, status: "Delivered", lat: 34.0522, lng: -118.2437, temp: "OK"}
    ]
    render json: shipments
  end
end
