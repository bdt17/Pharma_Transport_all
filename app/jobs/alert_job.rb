class AlertJob < ApplicationJob
  queue_as :default

  def perform(vehicle, geofence, event)
    ActionCable.server.broadcast("dashboard", {
      type: "geofence_alert",
      vehicle: vehicle.name,
      zone: geofence.name,
      event: event
    })
  end
end
