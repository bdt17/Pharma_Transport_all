class DriversController < ApplicationController
  def new
    @driver = Driver.new
  end

  def create
    @driver = Driver.new
    @driver.name = params[:driver][:name]
    @driver.phone_number = params[:driver][:phone_number]
    @driver.email = params[:driver][:email]
    @driver.encrypted_password = "$2a$12$demo_hash_for_pharma_transport"
    
    if @driver.save
      redirect_to '/drivers/dashboard', notice: "Welcome #{@driver.name}!"
    else
      render :new
    end
  end

  def dashboard
    @current_driver = Driver.last
  end

  def checkin
    truck = Vehicle.find_by(name: "Truck 001")
    if truck && params[:latitude] && params[:longitude]
      truck.update!(
        latitude: params[:latitude].to_f, 
        longitude: params[:longitude].to_f,
        updated_at: Time.current
      )
      render json: { status: 'success', truck: truck.name }
    else
      render json: { status: 'error', message: 'Truck 001 not found' }, status: 400
    end
  end
end
