class SensorsController < ApplicationController
  def live
    render json: {
      shipment_id: 123,
      current_temp: 4.2,
      threshold_low: 2.0, threshold_high: 8.0,
      status: "GREEN", timestamp: Time.now.utc.iso8601
    }
  end
end
