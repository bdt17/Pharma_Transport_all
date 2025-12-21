class CreateGpsReadings < ActiveRecord::Migration[8.1]
  def change
    create_table :gps_readings do |t|
      t.float :latitude
      t.float :longitude
      t.float :temperature
      t.integer :vehicle_id

      t.timestamps
    end
  end
end
