class CreateGeofences < ActiveRecord::Migration[8.1]
  def change
    create_table :geofences do |t|
      t.string :name
      t.string :boundary

      t.timestamps
    end
  end
end
