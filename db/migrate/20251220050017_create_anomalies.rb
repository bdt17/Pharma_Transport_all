class CreateAnomalies < ActiveRecord::Migration[8.1]
  def change
    create_table :anomalies do |t|
      t.references :truck, null: false, foreign_key: true
      t.string :type
      t.decimal :score
      t.boolean :alert_sent

      t.timestamps
    end
  end
end
