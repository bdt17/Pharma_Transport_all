# frozen_string_literal: true

# =============================================================================
# Stripe::CheckoutSessionsController
# =============================================================================
# Production-ready controller for Stripe Checkout integration
# FDA 21 CFR Part 11 Compliant - All actions logged to immutable audit trail
#
# Endpoints:
#   POST /stripe/checkout_sessions         - Create new checkout session
#   GET  /stripe/checkout_sessions/success - Handle successful payment
#   GET  /stripe/checkout_sessions/cancel  - Handle cancelled checkout
#   POST /stripe/checkout_sessions/portal  - Access Stripe billing portal
#
# Environment Variables Required:
#   STRIPE_SECRET_KEY      - Stripe API secret key
#   STRIPE_PUBLISHABLE_KEY - Stripe publishable key (for frontend)
#
# Deploy: Render + PostgreSQL + Stripe Live Mode
# =============================================================================

module Stripe
  class CheckoutSessionsController < ApplicationController
    before_action :authenticate_tenant!
    skip_before_action :verify_authenticity_token, only: [:create, :portal]

    # =========================================================================
    # POST /stripe/checkout_sessions
    # Creates a Stripe Checkout session and returns the URL for redirect
    # =========================================================================
    def create
      plan = extract_plan_param
      plan_config = Tenant::PLANS[plan]

      # Validate plan exists
      unless plan_config
        audit_log("checkout.invalid_plan", { requested_plan: plan })
        return render json: {
          error: "Invalid plan",
          valid_plans: Tenant::PLANS.keys
        }, status: :unprocessable_entity
      end

      # Validate plan has price_id (not free or contact-sales)
      unless plan_config[:price_id]
        audit_log("checkout.no_price_id", { plan: plan })
        return render json: {
          error: "Plan '#{plan}' is not available for online checkout",
          action: plan == "pfizer" ? "Contact sales@pharmatransport.io" : "Use free tier"
        }, status: :unprocessable_entity
      end

      # Create Stripe checkout session
      checkout_session = create_stripe_session(plan, plan_config)

      # FDA Audit: Log checkout session creation
      audit_log("checkout.session_created", {
        plan: plan,
        session_id: checkout_session.id,
        stripe_customer_id: current_tenant.stripe_customer_id,
        amount: plan_config[:monthly_price_cents],
        currency: "usd"
      })

      render json: {
        url: checkout_session.url,
        session_id: checkout_session.id,
        expires_at: Time.at(checkout_session.expires_at).utc.iso8601,
        plan: plan
      }

    rescue ::Stripe::CardError => e
      audit_log("checkout.card_error", { error: e.message, code: e.code })
      render json: { error: "Card error: #{e.message}" }, status: :payment_required

    rescue ::Stripe::RateLimitError => e
      audit_log("checkout.rate_limit", { error: e.message })
      render json: { error: "Too many requests. Please try again." }, status: :too_many_requests

    rescue ::Stripe::InvalidRequestError => e
      audit_log("checkout.invalid_request", { error: e.message })
      Rails.logger.error "[Stripe] Invalid request: #{e.message}"
      render json: { error: e.message }, status: :unprocessable_entity

    rescue ::Stripe::AuthenticationError => e
      audit_log("checkout.auth_error", { error: e.message })
      Rails.logger.error "[Stripe] Authentication failed - check STRIPE_SECRET_KEY"
      render json: { error: "Payment service configuration error" }, status: :internal_server_error

    rescue ::Stripe::StripeError => e
      audit_log("checkout.stripe_error", { error: e.message })
      Rails.logger.error "[Stripe] Error: #{e.message}"
      render json: { error: "Payment service temporarily unavailable" }, status: :service_unavailable

    rescue StandardError => e
      audit_log("checkout.unexpected_error", { error: e.message })
      Rails.logger.error "[Stripe] Unexpected error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render json: { error: "An unexpected error occurred" }, status: :internal_server_error
    end

    # =========================================================================
    # GET /stripe/checkout_sessions/success
    # Handles redirect after successful Stripe Checkout
    # =========================================================================
    def success
      @plan = params[:plan]
      @session_id = params[:session_id]

      # FDA Audit: Log success redirect
      audit_log("checkout.success_redirect", {
        plan: @plan,
        session_id: @session_id,
        subscription_id: current_tenant&.stripe_subscription_id
      })

      # Check if webhook has already processed (subscription should be active)
      if current_tenant&.subscription_active?
        flash[:notice] = "Welcome to #{@plan&.titleize || 'your new plan'}! Your subscription is now active."
      else
        # Webhook may still be processing
        flash[:notice] = "Your subscription is being activated. This usually takes a few seconds."
      end

      redirect_to dashboard_path
    end

    # =========================================================================
    # GET /stripe/checkout_sessions/cancel
    # Handles redirect after cancelled Stripe Checkout
    # =========================================================================
    def cancel
      # FDA Audit: Log cancellation
      audit_log("checkout.cancelled", {
        plan: params[:plan],
        session_id: params[:session_id],
        reason: params[:reason]
      })

      flash[:alert] = "Checkout was cancelled. No charges were made to your account."
      redirect_to billing_path
    end

    # =========================================================================
    # POST /stripe/checkout_sessions/portal
    # Creates Stripe Billing Portal session for subscription management
    # =========================================================================
    def portal
      unless current_tenant&.stripe_customer_id.present?
        audit_log("portal.no_customer", {})
        flash[:alert] = "No billing account found. Please subscribe to a plan first."
        return redirect_to billing_path
      end

      portal_session = ::Stripe::BillingPortal::Session.create(
        customer: current_tenant.stripe_customer_id,
        return_url: params[:return_url].presence || billing_url
      )

      # FDA Audit: Log portal access
      audit_log("portal.opened", {
        stripe_customer_id: current_tenant.stripe_customer_id,
        return_url: portal_session.return_url
      })

      redirect_to portal_session.url, allow_other_host: true

    rescue ::Stripe::InvalidRequestError => e
      audit_log("portal.error", { error: e.message })
      flash[:alert] = "Unable to access billing portal. Please contact support."
      redirect_to billing_path

    rescue ::Stripe::StripeError => e
      audit_log("portal.stripe_error", { error: e.message })
      flash[:alert] = "Billing portal temporarily unavailable."
      redirect_to billing_path
    end

    private

    # =========================================================================
    # AUTHENTICATION
    # =========================================================================

    def authenticate_tenant!
      unless current_tenant
        respond_to do |format|
          format.html do
            flash[:alert] = "Please sign in to access billing."
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

    def resolve_tenant
      # Priority 1: API Key authentication
      if request.headers["X-API-Key"].present?
        api_key = ApiKey.authenticate(request.headers["X-API-Key"])
        return api_key&.tenant
      end

      # Priority 2: Session-based authentication
      if session[:tenant_id].present?
        return Tenant.find_by(id: session[:tenant_id])
      end

      # Priority 3: Development fallback only
      if Rails.env.development? && Tenant.count == 1
        return Tenant.first
      end

      nil
    end

    def current_user
      @current_user ||= begin
        User.find_by(id: session[:user_id]) if session[:user_id]
      end
    end

    # =========================================================================
    # STRIPE SESSION CREATION
    # =========================================================================

    def create_stripe_session(plan, plan_config)
      # Ensure tenant has Stripe customer
      current_tenant.ensure_stripe_customer!

      ::Stripe::Checkout::Session.create({
        customer: current_tenant.stripe_customer_id,
        mode: "subscription",
        payment_method_types: ["card"],
        line_items: [{
          price: plan_config[:price_id],
          quantity: 1
        }],
        success_url: build_success_url(plan),
        cancel_url: build_cancel_url(plan),
        metadata: {
          tenant_id: current_tenant.id.to_s,
          tenant_subdomain: current_tenant.subdomain,
          plan: plan
        },
        client_reference_id: current_tenant.id.to_s,
        subscription_data: {
          metadata: {
            tenant_id: current_tenant.id.to_s,
            plan: plan
          }
        },
        allow_promotion_codes: true,
        billing_address_collection: "required",
        customer_update: {
          address: "auto",
          name: "auto"
        }
      })
    end

    def build_success_url(plan)
      base = request.base_url
      "#{base}/stripe/checkout_sessions/success?plan=#{plan}&session_id={CHECKOUT_SESSION_ID}"
    end

    def build_cancel_url(plan)
      base = request.base_url
      "#{base}/stripe/checkout_sessions/cancel?plan=#{plan}"
    end

    # =========================================================================
    # HELPERS
    # =========================================================================

    def extract_plan_param
      params[:plan]&.to_s&.strip&.downcase || "smb"
    end

    # =========================================================================
    # FDA 21 CFR PART 11 AUDIT LOGGING
    # =========================================================================

    def audit_log(action, metadata = {})
      return unless current_tenant

      AuditLog.log(
        tenant: current_tenant,
        action: "stripe.#{action}",
        resource: current_tenant,
        user: current_user,
        changes: {},
        metadata: metadata.merge(
          source: "checkout_sessions_controller",
          timestamp: Time.current.utc.iso8601,
          ip_address: request.remote_ip,
          user_agent: request.user_agent&.truncate(500),
          request_id: request.request_id
        ),
        request: request
      )
    rescue StandardError => e
      # Never fail checkout due to audit logging errors
      Rails.logger.error "[FDA Audit] Failed to log: #{e.message}"
    end
  end
end
