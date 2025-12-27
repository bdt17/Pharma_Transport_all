# frozen_string_literal: true

# =============================================================================
# RequireActiveSubscription Concern
# =============================================================================
# Blocks dashboard and API access for unpaid/inactive tenants
# FDA 21 CFR Part 11 Compliant - Access denials are logged
#
# Usage in controllers:
#   class DashboardController < ApplicationController
#     include RequireActiveSubscription
#   end
#
# Skip for specific actions:
#   class ApiController < ApplicationController
#     include RequireActiveSubscription
#     skip_before_action :require_active_subscription!, only: [:health, :status]
#   end
#
# Override skip logic in controller:
#   def skip_subscription_check?
#     action_name.in?(%w[index show])
#   end
#
# Deploy: Render + PostgreSQL + Stripe Live Mode
# =============================================================================

module RequireActiveSubscription
  extend ActiveSupport::Concern

  included do
    before_action :require_active_subscription!, unless: :skip_subscription_check?
  end

  private

  # ===========================================================================
  # MAIN CHECK
  # ===========================================================================

  def require_active_subscription!
    # Skip if no tenant context (let auth handle it)
    return if current_tenant.nil?

    # Check if tenant has access
    return if tenant_has_access?

    # Log access denial for FDA compliance
    log_access_denied

    # Handle the denial
    handle_subscription_required
  end

  # ===========================================================================
  # ACCESS DETERMINATION
  # ===========================================================================

  def tenant_has_access?
    # Free tier always has basic access
    return true if current_tenant.plan == "free" && current_tenant.active?

    # Active paid subscription
    return true if current_tenant.subscription_active?

    # Active trial
    return true if current_tenant.subscription_trialing? && trial_not_expired?

    # Trial period (legacy check)
    return true if current_tenant.trialing? && trial_not_expired?

    # Grace period (7 days after failed payment)
    return true if grace_period_active?

    # Use tenant's own access method if available
    return true if current_tenant.respond_to?(:has_dashboard_access?) && current_tenant.has_dashboard_access?

    false
  end

  def trial_not_expired?
    return true unless current_tenant.respond_to?(:trial_ends_at)
    return true if current_tenant.trial_ends_at.nil?

    current_tenant.trial_ends_at > Time.current
  end

  def grace_period_active?
    return false unless current_tenant.respond_to?(:last_payment_at)
    return false if current_tenant.last_payment_at.nil?
    return false unless current_tenant.subscription_past_due?

    # 7-day grace period
    current_tenant.last_payment_at > 7.days.ago
  end

  # ===========================================================================
  # HANDLE SUBSCRIPTION REQUIRED
  # ===========================================================================

  def handle_subscription_required
    respond_to do |format|
      format.html { handle_html_subscription_required }
      format.json { handle_json_subscription_required }
      format.any { handle_json_subscription_required }
    end
  end

  def handle_html_subscription_required
    flash[:alert] = subscription_alert_message
    redirect_to billing_path
  end

  def handle_json_subscription_required
    render json: {
      error: "subscription_required",
      code: subscription_error_code,
      message: subscription_alert_message,
      subscription_status: current_tenant.subscription_status,
      plan: current_tenant.plan,
      billing_url: billing_url,
      actions: available_actions
    }, status: :payment_required
  end

  # ===========================================================================
  # ERROR MESSAGES
  # ===========================================================================

  def subscription_alert_message
    case current_tenant.subscription_status
    when "canceled"
      "Your subscription has been canceled. Please resubscribe to continue using PharmaTransport."
    when "past_due"
      if grace_period_active?
        days_left = ((current_tenant.last_payment_at + 7.days - Time.current) / 1.day).ceil
        "Your payment is past due. You have #{days_left} days remaining in your grace period. Please update your payment method."
      else
        "Your payment is past due and grace period has expired. Please update your payment method to restore access."
      end
    when "unpaid"
      "Your account has been suspended due to non-payment. Please update your payment method to restore access."
    when "incomplete"
      "Your subscription setup is incomplete. Please complete the payment process."
    when "incomplete_expired"
      "Your subscription setup has expired. Please start a new subscription."
    when "trialing"
      "Your trial has expired. Please subscribe to continue using PharmaTransport."
    else
      "An active subscription is required to access this feature. Please subscribe to continue."
    end
  end

  def subscription_error_code
    case current_tenant.subscription_status
    when "canceled" then "subscription_canceled"
    when "past_due" then "payment_past_due"
    when "unpaid" then "account_suspended"
    when "incomplete", "incomplete_expired" then "subscription_incomplete"
    when "trialing" then "trial_expired"
    else "subscription_required"
    end
  end

  def available_actions
    actions = []

    case current_tenant.subscription_status
    when "canceled", "incomplete_expired"
      actions << { action: "subscribe", url: billing_url, label: "Subscribe Now" }
    when "past_due", "unpaid"
      actions << { action: "update_payment", url: billing_portal_url, label: "Update Payment Method" }
    when "incomplete"
      actions << { action: "complete_payment", url: billing_url, label: "Complete Payment" }
    when "trialing"
      actions << { action: "subscribe", url: billing_url, label: "Subscribe Now" }
    else
      actions << { action: "subscribe", url: billing_url, label: "View Plans" }
    end

    actions << { action: "contact_support", url: "mailto:support@pharmatransport.io", label: "Contact Support" }
    actions
  end

  def billing_portal_url
    current_tenant.billing_portal_url(return_url: request.original_url)
  rescue StandardError
    billing_url
  end

  # ===========================================================================
  # SKIP LOGIC
  # ===========================================================================

  def skip_subscription_check?
    # Override in controller to skip check for specific actions
    # Example: health checks, public endpoints, etc.
    false
  end

  # ===========================================================================
  # CURRENT TENANT (should be defined in ApplicationController)
  # ===========================================================================

  def current_tenant
    @current_tenant
  end

  # ===========================================================================
  # FDA AUDIT LOGGING
  # ===========================================================================

  def log_access_denied
    return unless current_tenant

    AuditLog.log(
      tenant: current_tenant,
      action: "access.subscription_required",
      resource: current_tenant,
      user: respond_to?(:current_user) ? current_user : nil,
      metadata: {
        source: "require_active_subscription",
        subscription_status: current_tenant.subscription_status,
        plan: current_tenant.plan,
        path: request.path,
        method: request.method,
        timestamp: Time.current.utc.iso8601,
        ip_address: request.remote_ip
      },
      request: request
    )
  rescue StandardError => e
    Rails.logger.error "[FDA Audit] Failed to log access denial: #{e.message}"
  end
end
