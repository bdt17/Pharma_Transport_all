class CreateSensorReadings < ActiveRecord::Migration[8.1]
  def change
    create_table :sensor_readings do |t|
      t.references :vehicle, null: false, foreign_key: true
      t.float :temperature
      t.float :humidity

      t.timestamps
    end
  end
end
