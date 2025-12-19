# app/models/vehicle.rb
class Vehicle < ApplicationRecord
  after_create :check_geofences

  def check_geofences
    Geofence.where("ST_Within(ST_Point(longitude, latitude), boundary)").each do |zone|
      AlertJob.perform_later(self, zone, :entry)
    end
  end
end
