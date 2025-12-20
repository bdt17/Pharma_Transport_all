class AddMissingGeofenceColumns < ActiveRecord::Migration[8.1]
  def change
    add_column :geofences, :latitude, :float unless column_exists?(:geofences, :latitude)
    add_column :geofences, :longitude, :float unless column_exists?(:geofences, :longitude)
    add_column :geofences, :radius, :float unless column_exists?(:geofences, :radius)
  end
end
