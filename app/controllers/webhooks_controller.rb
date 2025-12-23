class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  def receive
    payload = JSON.parse(request.body.read)
    Shipment.create!(pfizer_id: payload['shipment_id'], status: payload['status'])
    head :ok
  end
end

  def receive
    render json: {status: "PHARMA WEBHOOK OK 🚚", pfizer_shipment: params[:shipment_id]}
  end
