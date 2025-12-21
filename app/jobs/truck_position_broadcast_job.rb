class TruckPositionBroadcastJob < ApplicationJob
  queue_as :default

  def perform(truck_id, lat, lng)
    ActionCable.server.broadcast "truck_positions", {
      truck_id: truck_id,
      lat: lat,
      lng: lng,
      timestamp: Time.current.to_i
    }
  end
end
