class Location < ApplicationRecord
  belongs_to :vehicle  # Changed from truck
  after_create_commit :broadcast_location
  after_create_commit :check_temperature

  private
  def broadcast_location
    broadcast_append_to vehicle
  end

  def check_temperature
    TempAlertJob.perform_later(vehicle_id, temperature) if temperature && temperature > 8.0
  end
end
