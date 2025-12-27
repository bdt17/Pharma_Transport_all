class AuditsController < ApplicationController
  def shipment_log
    render json: [
      {timestamp: Time.now.utc, action: "Temp Check", temp: 4.2, compliant: true},
      {timestamp: 1.hour.ago.utc, action: "GPS Update", lat: 33.4484, compliant: true}
    ]
  end
end
