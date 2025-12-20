class AddGeofenceColumns < ActiveRecord::Migration[8.1]
  def change
    add_column :geofences, :name, :string
    add_column :geofences, :latitude, :float
    add_column :geofences, :longitude, :float
    add_column :geofences, :radius, :float
  end
end
