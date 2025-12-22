class Api::V1::RealtimeController < ApplicationController
  def index
    render json: {status: "GPS LIVE", vehicles: 3}
  end
end
