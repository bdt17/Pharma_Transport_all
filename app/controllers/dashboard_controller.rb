# frozen_string_literal: true

# =============================================================================
# DashboardController
# =============================================================================
# Main tenant dashboard with subscription enforcement
# FDA 21 CFR Part 11 Compliant - All access logged
#
# Requires active subscription for most actions
# Deploy: Render + PostgreSQL + Stripe Live Mode
# =============================================================================

class DashboardController < ApplicationController
  include RequireActiveSubscription

  before_action :authenticate_tenant!
  before_action :set_tenant_data

  # Skip subscription check for billing-related views
  def skip_subscription_check?
    action_name.in?(%w[subscription_required])
  end

  # =========================================================================
  # GET /dashboard
  # Main dashboard view
  # =========================================================================
  def index
    @stats = {
      shipments_active: @tenant.shipments.where(status: "in_transit").count,
      shipments_total: @tenant.shipments.count,
      alerts_open: @tenant.alerts.where(status: "open").count,
      temperature_events: @tenant.temperature_events.where("recorded_at > ?", 24.hours.ago).count,
      trucks_limit: @tenant.truck_limit || "Unlimited",
      trucks_remaining: @tenant.trucks_remaining || "Unlimited"
    }

    @recent_shipments = @tenant.shipments
                               .includes(:alerts, :temperature_events)
                               .order(created_at: :desc)
                               .limit(10)

    @recent_alerts = @tenant.alerts
                            .where(status: %w[open acknowledged])
                            .order(created_at: :desc)
                            .limit(5)

    # FDA Audit: Log dashboard access
    log_dashboard_access("index")
  end

  # =========================================================================
  # GET /dashboard/shipments
  # Live fleet tracking view
  # =========================================================================
  def shipments
    @shipments = @tenant.shipments
                        .includes(:alerts, :temperature_events, :geofence_events)
                        .order(created_at: :desc)
                        .limit(100)

    @excursion_count = @tenant.temperature_events.where(excursion: true).count
    log_dashboard_access("shipments")
  end

  # =========================================================================
  # GET /dashboard/audit_trail
  # FDA 21 CFR Part 11 audit trail view
  # =========================================================================
  def audit_trail
    @audit_logs = @tenant.audit_logs
                         .includes(:user, :api_key)
                         .order(created_at: :desc)
                         .limit(500)

    @chain_verification = AuditLog.verify_chain(tenant_id: @tenant.id)
    log_dashboard_access("audit_trail")
  end

  # =========================================================================
  # GET /dashboard/subscription_required
  # Shown when subscription is inactive
  # =========================================================================
  def subscription_required
    @subscription_status = @tenant&.subscription_status
    @plan = @tenant&.plan
    render :subscription_required
  end

  private

  # =========================================================================
  # AUTHENTICATION
  # =========================================================================

  def authenticate_tenant!
    unless current_tenant
      respond_to do |format|
        format.html do
          flash[:alert] = "Please sign in to access the dashboard."
          redirect_to root_path
        end
        format.json do
          render json: { error: "Authentication required" }, status: :unauthorized
        end
      end
    end
  end

  def current_tenant
    @current_tenant ||= resolve_tenant
  end
  helper_method :current_tenant

  def resolve_tenant
    if request.headers["X-API-Key"].present?
      api_key = ApiKey.authenticate(request.headers["X-API-Key"])
      return api_key&.tenant
    end

    if session[:tenant_id].present?
      return Tenant.find_by(id: session[:tenant_id])
    end

    # Development fallback
    Tenant.first if Rails.env.development?
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end
  helper_method :current_user

  def set_tenant_data
    @tenant = current_tenant
    @subscription_active = @tenant&.has_billing_access?
    @plan = @tenant&.plan
    @subscription_status = @tenant&.subscription_status
  end

  # =========================================================================
  # FDA AUDIT LOGGING
  # =========================================================================

  def log_dashboard_access(action)
    return unless @tenant

    AuditLog.log(
      tenant: @tenant,
      action: "dashboard.#{action}",
      resource: @tenant,
      user: current_user,
      metadata: {
        source: "dashboard_controller",
        timestamp: Time.current.utc.iso8601,
        ip_address: request.remote_ip
      },
      request: request
    )
  rescue StandardError => e
    Rails.logger.error "[FDA Audit] Dashboard access log failed: #{e.message}"
  end
end
