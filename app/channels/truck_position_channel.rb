class TruckPositionChannel < ApplicationCable::Channel
  def subscribed
    # stream_from "some_channel"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end

class TruckPositionChannel < ApplicationCable::Channel
  def subscribed
    stream_from "truck_positions"
  end
end




