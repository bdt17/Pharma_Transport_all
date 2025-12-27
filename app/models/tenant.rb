# frozen_string_literal: true

# =============================================================================
# Tenant Model
# =============================================================================
# Multi-tenant SaaS model with Stripe subscription integration
# FDA 21 CFR Part 11 Compliant - All changes tracked via PaperTrail
#
# Stripe Fields:
#   - stripe_customer_id     : Stripe Customer ID (cus_xxx)
#   - stripe_subscription_id : Stripe Subscription ID (sub_xxx)
#   - subscription_status    : Mirrors Stripe subscription.status
#   - plan                   : Current plan (free, smb, enterprise, pfizer)
#   - billing_email          : Email for invoices
#   - last_payment_at        : Last successful payment timestamp
#   - trial_ends_at          : Trial expiration (if applicable)
#
# Deploy: Render + PostgreSQL + Stripe Live Mode
# =============================================================================

class Tenant < ApplicationRecord
  # ===========================================================================
  # FDA 21 CFR PART 11 AUDIT TRAIL
  # ===========================================================================
  has_paper_trail versions: { class_name: "PaperTrail::Version" },
                  ignore: [:api_call_count, :last_api_call_at, :updated_at]

  # ===========================================================================
  # ASSOCIATIONS
  # ===========================================================================
  has_many :users, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :shipments, dependent: :destroy
  has_many :temperature_events, dependent: :destroy
  has_many :geofence_events, dependent: :destroy
  has_many :alerts, dependent: :destroy
  has_many :audit_logs, dependent: :destroy
  has_many :stripe_events, dependent: :destroy

  # ===========================================================================
  # CALLBACKS
  # ===========================================================================
  before_create :create_stripe_customer
  after_update :log_subscription_change, if: :saved_change_to_subscription_status?

  # ===========================================================================
  # VALIDATIONS
  # ===========================================================================
  validates :name, presence: true
  validates :subdomain, presence: true, uniqueness: { case_sensitive: false },
            format: { with: /\A[a-z0-9][a-z0-9-]*[a-z0-9]\z/i,
                      message: "must start/end with alphanumeric, can contain hyphens" },
            length: { minimum: 3, maximum: 63 }
  validates :stripe_customer_id, uniqueness: true, allow_nil: true
  validates :stripe_subscription_id, uniqueness: true, allow_nil: true
  validates :billing_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :plan, inclusion: { in: ->(_) { PLANS.keys } }, allow_nil: true
  validates :subscription_status, inclusion: { in: SUBSCRIPTION_STATUSES }, allow_nil: true

  # ===========================================================================
  # SCOPES
  # ===========================================================================
  scope :active, -> { where(status: "active") }
  scope :trialing, -> { where(status: "trialing") }
  scope :canceled, -> { where(status: "canceled") }
  scope :suspended, -> { where(status: "suspended") }
  scope :past_due, -> { where(subscription_status: "past_due") }
  scope :paying, -> { where.not(plan: "free") }
  scope :with_stripe, -> { where.not(stripe_customer_id: nil) }

  # ===========================================================================
  # PLAN CONFIGURATION
  # ===========================================================================
  PLANS = {
    "free" => {
      trucks: 5,
      api_calls: 1_000,
      price_id: nil,
      monthly_price_cents: 0,
      features: ["5 trucks", "1K API calls/mo", "FDA audit trail"]
    },
    "smb" => {
      trucks: 25,
      api_calls: 50_000,
      price_id: ENV.fetch("STRIPE_PRICE_SMB", "price_smb_monthly"),
      monthly_price_cents: 9900,
      features: ["25 trucks", "50K API calls/mo", "FDA audit trail", "Priority support"]
    },
    "enterprise" => {
      trucks: 200,
      api_calls: 500_000,
      price_id: ENV.fetch("STRIPE_PRICE_ENTERPRISE", "price_enterprise_monthly"),
      monthly_price_cents: 200000,
      features: ["200 trucks", "500K API calls/mo", "FDA audit trail", "Priority support", "Custom integrations"]
    },
    "pfizer" => {
      trucks: Float::INFINITY,
      api_calls: Float::INFINITY,
      price_id: ENV.fetch("STRIPE_PRICE_PFIZER", nil),
      monthly_price_cents: nil, # Contact sales
      features: ["Unlimited trucks", "Unlimited API calls", "FDA audit trail", "Dedicated account manager", "SLA guarantees"]
    }
  }.freeze

  SUBSCRIPTION_STATUSES = %w[
    active
    past_due
    unpaid
    canceled
    trialing
    incomplete
    incomplete_expired
  ].freeze

  # ===========================================================================
  # TENANT STATUS METHODS
  # ===========================================================================

  def active?
    status == "active"
  end

  def trialing?
    status == "trialing"
  end

  def canceled?
    status == "canceled"
  end

  def suspended?
    status == "suspended"
  end

  def inactive?
    !active? && !trialing?
  end

  # ===========================================================================
  # SUBSCRIPTION STATUS METHODS
  # ===========================================================================

  def subscription_active?
    subscription_status == "active"
  end

  def subscription_trialing?
    subscription_status == "trialing"
  end

  def subscription_past_due?
    subscription_status == "past_due"
  end

  def subscription_unpaid?
    subscription_status == "unpaid"
  end

  def subscription_canceled?
    subscription_status == "canceled"
  end

  def subscription_incomplete?
    subscription_status&.start_with?("incomplete")
  end

  # ===========================================================================
  # ACCESS CONTROL
  # ===========================================================================

  # 7-day grace period for past_due subscriptions
  def subscription_in_grace_period?
    subscription_past_due? && last_payment_at.present? && last_payment_at > 7.days.ago
  end

  # Trial still valid?
  def trial_active?
    trialing? && trial_ends_at.present? && trial_ends_at > Time.current
  end

  # Can tenant access paid features?
  def has_billing_access?
    subscription_active? ||
      subscription_trialing? ||
      trial_active? ||
      subscription_in_grace_period?
  end

  # Can tenant access the dashboard at all?
  def has_dashboard_access?
    return true if plan == "free" && active?
    has_billing_access?
  end

  # Can tenant access API?
  def has_api_access?
    has_dashboard_access? && within_api_limit?
  end

  # ===========================================================================
  # STRIPE: AUTO-CREATE CUSTOMER
  # ===========================================================================

  def create_stripe_customer
    return if stripe_customer_id.present?
    return unless billing_email.present? || name.present?

    customer = ::Stripe::Customer.create(
      name: name,
      email: billing_email.presence || "#{subdomain}@pharmatransport.io",
      metadata: {
        tenant_id: id || "pending",
        subdomain: subdomain,
        environment: Rails.env
      }
    )

    self.stripe_customer_id = customer.id
    Rails.logger.info "[Stripe] Created customer #{customer.id} for tenant #{subdomain}"

  rescue ::Stripe::StripeError => e
    Rails.logger.error "[Stripe] Failed to create customer for #{subdomain}: #{e.message}"
    # Don't block tenant creation if Stripe fails
    nil
  end

  # ===========================================================================
  # STRIPE: ENSURE CUSTOMER EXISTS
  # ===========================================================================

  def ensure_stripe_customer!
    return stripe_customer_id if stripe_customer_id.present?

    customer = ::Stripe::Customer.create(
      name: name,
      email: billing_email.presence || "#{subdomain}@pharmatransport.io",
      metadata: {
        tenant_id: id,
        subdomain: subdomain,
        environment: Rails.env
      }
    )

    update!(stripe_customer_id: customer.id)
    Rails.logger.info "[Stripe] Created customer #{customer.id} for tenant #{id}"
    customer.id
  end

  # ===========================================================================
  # STRIPE: CREATE CHECKOUT SESSION
  # ===========================================================================

  def create_checkout_session(plan_name:, success_url:, cancel_url:)
    plan_config = PLANS[plan_name]
    raise ArgumentError, "Invalid plan: #{plan_name}" unless plan_config
    raise ArgumentError, "Plan '#{plan_name}' not available online" unless plan_config[:price_id]

    ensure_stripe_customer!

    ::Stripe::Checkout::Session.create(
      customer: stripe_customer_id,
      mode: "subscription",
      payment_method_types: ["card"],
      line_items: [{
        price: plan_config[:price_id],
        quantity: 1
      }],
      success_url: success_url,
      cancel_url: cancel_url,
      metadata: { tenant_id: id.to_s, plan: plan_name },
      client_reference_id: id.to_s,
      subscription_data: {
        metadata: { tenant_id: id.to_s, plan: plan_name }
      },
      allow_promotion_codes: true
    )
  end

  # ===========================================================================
  # STRIPE: BILLING PORTAL
  # ===========================================================================

  def billing_portal_url(return_url:)
    return nil unless stripe_customer_id.present?

    session = ::Stripe::BillingPortal::Session.create(
      customer: stripe_customer_id,
      return_url: return_url
    )
    session.url
  end

  # ===========================================================================
  # STRIPE: CANCEL SUBSCRIPTION
  # ===========================================================================

  def cancel_subscription!(immediately: false)
    return unless stripe_subscription_id.present?

    if immediately
      ::Stripe::Subscription.cancel(stripe_subscription_id)
    else
      ::Stripe::Subscription.update(stripe_subscription_id, cancel_at_period_end: true)
    end

    update!(
      stripe_subscription_id: immediately ? nil : stripe_subscription_id,
      subscription_status: immediately ? "canceled" : subscription_status
    )

    Rails.logger.info "[Stripe] Subscription #{immediately ? 'cancelled' : 'scheduled for cancellation'} for tenant #{id}"

  rescue ::Stripe::StripeError => e
    Rails.logger.error "[Stripe] Failed to cancel subscription: #{e.message}"
    raise
  end

  # ===========================================================================
  # PLAN LIMITS
  # ===========================================================================

  def plan_config
    PLANS[plan] || PLANS["free"]
  end

  def truck_limit
    limit = plan_config[:trucks]
    limit == Float::INFINITY ? nil : limit
  end

  def api_call_limit
    limit = plan_config[:api_calls]
    limit == Float::INFINITY ? nil : limit
  end

  def monthly_price_cents
    plan_config[:monthly_price_cents]
  end

  def within_truck_limit?
    return true if plan_config[:trucks] == Float::INFINITY
    shipments.where(status: "in_transit").count < plan_config[:trucks]
  end

  def within_api_limit?
    return true if plan_config[:api_calls] == Float::INFINITY
    return true unless respond_to?(:api_call_count)
    (api_call_count || 0) < plan_config[:api_calls]
  end

  def trucks_remaining
    return nil if plan_config[:trucks] == Float::INFINITY
    [plan_config[:trucks] - shipments.where(status: "in_transit").count, 0].max
  end

  # ===========================================================================
  # USAGE STATS
  # ===========================================================================

  def usage_stats
    {
      tenant_id: id,
      subdomain: subdomain,
      plan: plan,
      status: status,
      subscription_status: subscription_status,
      trucks_active: shipments.where(status: "in_transit").count,
      trucks_limit: truck_limit || "unlimited",
      trucks_remaining: trucks_remaining || "unlimited",
      api_calls_used: api_call_count || 0,
      api_calls_limit: api_call_limit || "unlimited",
      has_billing_access: has_billing_access?,
      stripe_customer_id: stripe_customer_id,
      stripe_subscription_id: stripe_subscription_id,
      last_payment_at: last_payment_at&.utc&.iso8601
    }
  end

  # ===========================================================================
  # PRIVATE METHODS
  # ===========================================================================

  private

  def log_subscription_change
    Rails.logger.info "[Tenant] Subscription status changed for #{id}: #{saved_change_to_subscription_status.inspect}"
  end
end
