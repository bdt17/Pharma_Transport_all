class CreateGeofences < ActiveRecord::Migration[8.1]
  def change
    create_table :geofences do |t|
      t.string :name
      t.float :latitude
      t.float :longitude
      t.float :radius
      t.timestamps
    end
  end
end
