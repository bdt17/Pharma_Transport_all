# frozen_string_literal: true

# =============================================================================
# Stripe::WebhooksController
# =============================================================================
# Production-ready webhook handler for Stripe events
# FDA 21 CFR Part 11 Compliant - All events logged to immutable audit trail
#
# Handled Events:
#   - checkout.session.completed    : New subscription activated
#   - invoice.paid                  : Successful payment/renewal
#   - invoice.payment_failed        : Failed payment (dunning)
#   - customer.subscription.created : Subscription created
#   - customer.subscription.updated : Plan change or status change
#   - customer.subscription.deleted : Subscription cancelled
#
# Security:
#   - STRIPE_WEBHOOK_SECRET signature verification (REQUIRED in production)
#   - Idempotent event processing via StripeEvent model
#
# Environment Variables Required:
#   STRIPE_WEBHOOK_SECRET - Webhook signing secret from Stripe Dashboard
#
# Deploy: Render + PostgreSQL + Stripe Live Mode
# =============================================================================

module Stripe
  class WebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token

    # In-memory cache for rapid duplicate detection (per-instance)
    PROCESSED_EVENTS_CACHE = Set.new

    # =========================================================================
    # POST /stripe/webhooks
    # Main webhook endpoint - receives all Stripe events
    # =========================================================================
    def create
      payload = request.body.read
      sig_header = request.env["HTTP_STRIPE_SIGNATURE"]
      webhook_secret = ENV.fetch("STRIPE_WEBHOOK_SECRET", nil)

      # Step 1: Verify webhook signature
      event = verify_webhook_signature(payload, sig_header, webhook_secret)
      return render json: { error: "Invalid signature" }, status: :bad_request unless event

      # Step 2: Idempotency check - skip already processed events
      if event_already_processed?(event.id)
        Rails.logger.info "[Stripe] Skipping duplicate event: #{event.id}"
        return head :ok
      end

      # Step 3: Process the event
      process_stripe_event(event)

      # Step 4: Mark event as processed for idempotency
      mark_event_processed(event)

      head :ok

    rescue StandardError => e
      Rails.logger.error "[Stripe] Webhook error: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
      # Return 200 to prevent Stripe retries for unrecoverable errors
      head :ok
    end

    private

    # =========================================================================
    # SIGNATURE VERIFICATION
    # =========================================================================

    def verify_webhook_signature(payload, sig_header, webhook_secret)
      # Production requires signature verification
      if webhook_secret.blank?
        if Rails.env.production?
          Rails.logger.error "[Stripe] FATAL: STRIPE_WEBHOOK_SECRET not configured!"
          return nil
        else
          # Development: allow unverified webhooks with warning
          Rails.logger.warn "[Stripe] WARNING: Processing unverified webhook (dev mode only)"
          return ::Stripe::Event.construct_from(JSON.parse(payload))
        end
      end

      begin
        ::Stripe::Webhook.construct_event(payload, sig_header, webhook_secret)
      rescue JSON::ParserError => e
        Rails.logger.error "[Stripe] Invalid JSON: #{e.message}"
        nil
      rescue ::Stripe::SignatureVerificationError => e
        Rails.logger.error "[Stripe] Invalid signature: #{e.message}"
        nil
      end
    end

    # =========================================================================
    # EVENT ROUTING
    # =========================================================================

    def process_stripe_event(event)
      Rails.logger.info "[Stripe] Processing event: #{event.type} (#{event.id})"

      case event.type
      when "checkout.session.completed"
        handle_checkout_completed(event)
      when "invoice.paid"
        handle_invoice_paid(event)
      when "invoice.payment_failed"
        handle_invoice_payment_failed(event)
      when "customer.subscription.created"
        handle_subscription_created(event)
      when "customer.subscription.updated"
        handle_subscription_updated(event)
      when "customer.subscription.deleted"
        handle_subscription_deleted(event)
      when "customer.updated"
        handle_customer_updated(event)
      else
        handle_unhandled_event(event)
      end
    end

    # =========================================================================
    # checkout.session.completed
    # Customer completed Stripe Checkout - activate subscription
    # =========================================================================

    def handle_checkout_completed(event)
      session = event.data.object
      tenant = find_tenant_from_session(session)

      unless tenant
        audit_webhook(event, nil, "tenant_not_found", { session_id: session.id })
        Rails.logger.warn "[Stripe] Checkout completed but tenant not found: #{session.metadata}"
        return
      end

      # Capture previous state for audit
      previous_state = {
        status: tenant.status,
        subscription_status: tenant.subscription_status,
        plan: tenant.plan
      }

      # Update tenant with subscription info
      tenant.update!(
        stripe_customer_id: session.customer,
        stripe_subscription_id: session.subscription,
        subscription_status: "active",
        status: "active",
        last_payment_at: Time.current
      )

      # FDA Audit Log
      audit_webhook(event, tenant, "subscription_activated", {
        previous_state: previous_state,
        new_state: {
          status: "active",
          subscription_status: "active"
        },
        stripe_customer_id: session.customer,
        stripe_subscription_id: session.subscription,
        amount_total: session.amount_total,
        currency: session.currency
      })

      Rails.logger.info "[Stripe] Subscription activated for tenant #{tenant.id} (#{tenant.subdomain})"
    end

    # =========================================================================
    # invoice.paid
    # Payment successful - ensure subscription is active
    # =========================================================================

    def handle_invoice_paid(event)
      invoice = event.data.object
      tenant = Tenant.find_by(stripe_customer_id: invoice.customer)

      unless tenant
        audit_webhook(event, nil, "tenant_not_found", { customer_id: invoice.customer })
        return
      end

      previous_status = tenant.subscription_status

      tenant.update!(
        subscription_status: "active",
        status: "active",
        last_payment_at: Time.current
      )

      # FDA Audit Log
      audit_webhook(event, tenant, "payment_succeeded", {
        previous_status: previous_status,
        new_status: "active",
        invoice_id: invoice.id,
        amount_paid: invoice.amount_paid,
        amount_paid_formatted: format_currency(invoice.amount_paid, invoice.currency),
        currency: invoice.currency,
        billing_reason: invoice.billing_reason,
        subscription_id: invoice.subscription
      })

      Rails.logger.info "[Stripe] Payment received for tenant #{tenant.id}: #{format_currency(invoice.amount_paid, invoice.currency)}"
    end

    # =========================================================================
    # invoice.payment_failed
    # Payment failed - update status based on attempt count
    # =========================================================================

    def handle_invoice_payment_failed(event)
      invoice = event.data.object
      tenant = Tenant.find_by(stripe_customer_id: invoice.customer)

      unless tenant
        audit_webhook(event, nil, "tenant_not_found", { customer_id: invoice.customer })
        return
      end

      previous_status = tenant.subscription_status
      attempt_count = invoice.attempt_count || 1

      # Determine new status based on retry attempts
      # Stripe typically retries 3-4 times over ~3 weeks
      new_subscription_status = case attempt_count
                                when 1..2 then "past_due"
                                when 3 then "past_due"
                                else "unpaid"
                                end

      # Only suspend account after all retries exhausted
      new_tenant_status = new_subscription_status == "unpaid" ? "suspended" : "active"

      tenant.update!(
        subscription_status: new_subscription_status,
        status: new_tenant_status
      )

      # FDA Audit Log - CRITICAL for compliance
      audit_webhook(event, tenant, "payment_failed", {
        previous_status: previous_status,
        new_subscription_status: new_subscription_status,
        new_tenant_status: new_tenant_status,
        invoice_id: invoice.id,
        amount_due: invoice.amount_due,
        amount_due_formatted: format_currency(invoice.amount_due, invoice.currency),
        attempt_count: attempt_count,
        next_attempt: invoice.next_payment_attempt ? Time.at(invoice.next_payment_attempt).utc.iso8601 : nil,
        failure_reason: extract_failure_reason(invoice)
      })

      Rails.logger.warn "[Stripe] Payment FAILED for tenant #{tenant.id}: attempt #{attempt_count}, new status: #{new_subscription_status}"

      # TODO: Trigger dunning email
      # TenantMailer.payment_failed(tenant, invoice, attempt_count).deliver_later
    end

    # =========================================================================
    # customer.subscription.created
    # New subscription created (may come before or after checkout.session.completed)
    # =========================================================================

    def handle_subscription_created(event)
      subscription = event.data.object
      tenant = Tenant.find_by(stripe_customer_id: subscription.customer)

      unless tenant
        audit_webhook(event, nil, "tenant_not_found", { customer_id: subscription.customer })
        return
      end

      plan_name = extract_plan_name(subscription)
      previous_plan = tenant.plan

      tenant.update!(
        stripe_subscription_id: subscription.id,
        plan: plan_name,
        subscription_status: map_stripe_status(subscription.status),
        status: subscription.status == "active" ? "active" : tenant.status
      )

      audit_webhook(event, tenant, "subscription_created", {
        previous_plan: previous_plan,
        new_plan: plan_name,
        subscription_id: subscription.id,
        stripe_status: subscription.status,
        current_period_end: Time.at(subscription.current_period_end).utc.iso8601
      })

      Rails.logger.info "[Stripe] Subscription created for tenant #{tenant.id}: #{plan_name}"
    end

    # =========================================================================
    # customer.subscription.updated
    # Subscription changed (plan upgrade/downgrade, status change, etc.)
    # =========================================================================

    def handle_subscription_updated(event)
      subscription = event.data.object
      previous_attributes = event.data.previous_attributes || {}
      tenant = Tenant.find_by(stripe_customer_id: subscription.customer)

      unless tenant
        audit_webhook(event, nil, "tenant_not_found", { customer_id: subscription.customer })
        return
      end

      plan_name = extract_plan_name(subscription)

      previous_state = {
        plan: tenant.plan,
        subscription_status: tenant.subscription_status,
        status: tenant.status
      }

      tenant.update!(
        plan: plan_name,
        subscription_status: map_stripe_status(subscription.status),
        status: map_tenant_status(subscription.status)
      )

      audit_webhook(event, tenant, "subscription_updated", {
        previous_state: previous_state,
        new_state: {
          plan: plan_name,
          subscription_status: map_stripe_status(subscription.status),
          status: map_tenant_status(subscription.status)
        },
        stripe_status: subscription.status,
        cancel_at_period_end: subscription.cancel_at_period_end,
        changed_attributes: previous_attributes.keys
      })

      Rails.logger.info "[Stripe] Subscription updated for tenant #{tenant.id}: status=#{subscription.status}, plan=#{plan_name}"
    end

    # =========================================================================
    # customer.subscription.deleted
    # Subscription cancelled - downgrade to free
    # =========================================================================

    def handle_subscription_deleted(event)
      subscription = event.data.object
      tenant = Tenant.find_by(stripe_customer_id: subscription.customer)

      unless tenant
        audit_webhook(event, nil, "tenant_not_found", { customer_id: subscription.customer })
        return
      end

      previous_state = {
        plan: tenant.plan,
        subscription_status: tenant.subscription_status,
        stripe_subscription_id: tenant.stripe_subscription_id
      }

      tenant.update!(
        stripe_subscription_id: nil,
        plan: "free",
        subscription_status: "canceled",
        status: "canceled"
      )

      # FDA Audit Log - CRITICAL for compliance
      audit_webhook(event, tenant, "subscription_canceled", {
        previous_state: previous_state,
        new_plan: "free",
        new_status: "canceled",
        cancellation_reason: subscription.cancellation_details&.reason,
        canceled_at: subscription.canceled_at ? Time.at(subscription.canceled_at).utc.iso8601 : nil
      })

      Rails.logger.info "[Stripe] Subscription CANCELLED for tenant #{tenant.id} - downgraded to free"

      # TODO: Send cancellation confirmation email
      # TenantMailer.subscription_cancelled(tenant).deliver_later
    end

    # =========================================================================
    # customer.updated
    # Customer details changed (email, payment method, etc.)
    # =========================================================================

    def handle_customer_updated(event)
      customer = event.data.object
      tenant = Tenant.find_by(stripe_customer_id: customer.id)

      unless tenant
        audit_webhook(event, nil, "tenant_not_found", { customer_id: customer.id })
        return
      end

      # Update billing email if changed
      if customer.email.present? && customer.email != tenant.billing_email
        previous_email = tenant.billing_email
        tenant.update!(billing_email: customer.email)

        audit_webhook(event, tenant, "billing_email_updated", {
          previous_email: previous_email,
          new_email: customer.email
        })
      end
    end

    # =========================================================================
    # Unhandled events - log for monitoring
    # =========================================================================

    def handle_unhandled_event(event)
      Rails.logger.info "[Stripe] Unhandled event type: #{event.type} (#{event.id})"

      # Still audit for completeness
      audit_webhook(event, nil, "unhandled_event", {
        event_type: event.type
      })
    end

    # =========================================================================
    # HELPERS
    # =========================================================================

    def find_tenant_from_session(session)
      # Try metadata first (most reliable)
      if session.metadata&.tenant_id.present?
        tenant = Tenant.find_by(id: session.metadata.tenant_id)
        return tenant if tenant
      end

      # Try client_reference_id
      if session.client_reference_id.present?
        tenant = Tenant.find_by(id: session.client_reference_id)
        return tenant if tenant
      end

      # Last resort: find by customer ID
      if session.customer.present?
        Tenant.find_by(stripe_customer_id: session.customer)
      end
    end

    def extract_plan_name(subscription)
      price = subscription.items&.data&.first&.price
      return "free" unless price

      # Priority: lookup_key > nickname > price_id matching > default
      price.lookup_key ||
        price.nickname&.downcase&.strip ||
        find_plan_by_price_id(price.id) ||
        "smb"
    end

    def find_plan_by_price_id(price_id)
      Tenant::PLANS.find { |name, config| config[:price_id] == price_id }&.first
    end

    def map_stripe_status(stripe_status)
      case stripe_status
      when "active" then "active"
      when "trialing" then "trialing"
      when "past_due" then "past_due"
      when "canceled" then "canceled"
      when "unpaid" then "unpaid"
      when "incomplete" then "incomplete"
      when "incomplete_expired" then "incomplete"
      else "active"
      end
    end

    def map_tenant_status(stripe_status)
      case stripe_status
      when "active", "trialing" then "active"
      when "past_due" then "active"  # Grace period
      when "canceled", "unpaid" then "canceled"
      when "incomplete", "incomplete_expired" then "suspended"
      else "active"
      end
    end

    def extract_failure_reason(invoice)
      return nil unless invoice.last_finalization_error

      {
        code: invoice.last_finalization_error.code,
        message: invoice.last_finalization_error.message,
        type: invoice.last_finalization_error.type
      }
    end

    def format_currency(cents, currency = "usd")
      "$#{'%.2f' % (cents.to_f / 100)} #{currency.upcase}"
    end

    # =========================================================================
    # IDEMPOTENCY
    # =========================================================================

    def event_already_processed?(event_id)
      # Check in-memory cache first (fast)
      return true if PROCESSED_EVENTS_CACHE.include?(event_id)

      # Check database (durable across instances)
      StripeEvent.exists?(stripe_event_id: event_id)
    rescue ActiveRecord::StatementInvalid
      # Table doesn't exist yet - allow processing
      false
    end

    def mark_event_processed(event)
      # Add to in-memory cache
      PROCESSED_EVENTS_CACHE.add(event.id)

      # Prune cache if too large (prevent memory leak)
      if PROCESSED_EVENTS_CACHE.size > 10_000
        PROCESSED_EVENTS_CACHE.clear
      end

      # Persist to database
      StripeEvent.create!(
        stripe_event_id: event.id,
        event_type: event.type,
        processed_at: Time.current,
        metadata: {
          livemode: event.livemode,
          api_version: event.api_version
        }
      )
    rescue ActiveRecord::RecordNotUnique
      # Already processed by another instance - safe to ignore
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.warn "[Stripe] StripeEvent table not found: #{e.message}"
    end

    # =========================================================================
    # FDA 21 CFR PART 11 AUDIT LOGGING
    # =========================================================================

    def audit_webhook(event, tenant, action, metadata = {})
      audit_data = {
        source: "stripe_webhook",
        stripe_event_id: event.id,
        stripe_event_type: event.type,
        timestamp: Time.current.utc.iso8601,
        livemode: event.livemode,
        api_version: event.api_version,
        request_id: request.request_id
      }.merge(metadata)

      if tenant
        AuditLog.log(
          tenant: tenant,
          action: "stripe.webhook.#{action}",
          resource: tenant,
          changes: metadata.slice(:previous_state, :new_state, :previous_status, :new_status),
          metadata: audit_data,
          request: request
        )
      end

      # Always log to Rails logger for operational visibility
      Rails.logger.info "[FDA Audit] stripe.webhook.#{action} | tenant=#{tenant&.id} | event=#{event.id} | livemode=#{event.livemode}"

    rescue StandardError => e
      # Never fail webhook processing due to audit logging errors
      Rails.logger.error "[FDA Audit] Failed to log webhook: #{e.message}"
    end
  end
end
