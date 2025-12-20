task anomaly_detection: :environment do
  Vehicle.where("temperature > 8 OR gps_speed > 80").update_all(alert_sent: true)
  puts "✅ #{Vehicle.where(alert_sent: true).count} anomalies detected"
end
