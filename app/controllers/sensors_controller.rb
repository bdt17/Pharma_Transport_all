class SensorsController < ApplicationController
  def index
    render json: [{id:1,truck_id:1,temperature:4.2,"PHARMA":"TRUCK SENSORS 🚚 FDA"}]
  end
end
