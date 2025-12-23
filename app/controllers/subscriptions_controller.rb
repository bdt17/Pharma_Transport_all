class SubscriptionsController < ApplicationController
  def new
    @plans = Plan.plans
  end

  def create
    customer = Stripe::Customer.create(email: current_user.email)
    subscription = Stripe::Subscription.create(
      customer: customer.id,
      items: [{ price: params[:plan_id] }]
    )
    
    current_user.organization.update!(
      stripe_customer_id: customer.id
    )
    current_user.organization.create_subscription!(
      stripe_subscription_id: subscription.id, 
      status: 'active', 
      plan: params[:plan_id]
    )
    
    redirect_to dashboard_path, notice: "Enterprise active!"
  end
end
