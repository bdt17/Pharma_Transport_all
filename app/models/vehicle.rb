class Vehicle < ApplicationRecord
  after_create :check_geofences
has_many :locations, -> { order(created_at: :desc) }

  def check_geofences
    Geofence.find_each do |zone|
      # Haversine approx for Phoenix Depot (33.4484, -112.0740)
      distance = Math.sqrt(
        (latitude - 33.4484)**2 + (longitude + 112.0740)**2
      ) * 111.0  # km
      
      if distance < 0.5  # 500m radius
        AlertJob.perform_later(self, zone, :entry)
        puts "🚨 GEOFENCE: #{name} → #{zone.name}"
      end
    end
  end
end
