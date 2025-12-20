class DriversController < ApplicationController
  def new
    render layout: 'dashboard'
  end
  
  def create
    # Driver signup logic
    redirect_to dashboard_path, notice: 'Driver added!'
  end
end
