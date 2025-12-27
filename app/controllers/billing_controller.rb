# frozen_string_literal: true

# Phase 3: Billing Controller
# Manages tenant subscription and billing UI

class BillingController < ApplicationController
  before_action :set_tenant

  # GET /billing
  def index
    @plans = Tenant::PLANS
    @current_plan = @tenant&.plan || "free"
    @usage = @tenant&.usage_stats || {}
  end

  # GET /billing/plans
  def plans
    render json: {
      plans: Tenant::PLANS.map do |name, config|
        {
          name: name,
          trucks: config[:trucks] == Float::INFINITY ? "unlimited" : config[:trucks],
          api_calls: config[:api_calls] == Float::INFINITY ? "unlimited" : config[:api_calls],
          price_id: config[:price_id]
        }
      end,
      current_plan: @tenant&.plan
    }
  end

  # POST /billing/subscribe
  def subscribe
    plan = params[:plan]

    unless Tenant::PLANS.key?(plan)
      return render json: { error: "Invalid plan" }, status: :unprocessable_entity
    end

    if plan == "free"
      @tenant.set_plan("free")
      render json: { success: true, message: "Downgraded to free plan" }
    else
      session = @tenant.create_checkout_session(
        plan_name: plan,
        success_url: "#{request.base_url}/stripe/checkout_sessions/success?plan=#{plan}",
        cancel_url: "#{request.base_url}/billing"
      )
      render json: { checkout_url: session.url }
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_tenant
    @tenant = current_tenant
  end

  def current_tenant
    @current_tenant ||= begin
      if session[:tenant_id]
        Tenant.find_by(id: session[:tenant_id])
      elsif request.headers["X-API-Key"]
        api_key = ApiKey.authenticate(request.headers["X-API-Key"])
        api_key&.tenant
      else
        Tenant.first
      end
    end
  end
end
