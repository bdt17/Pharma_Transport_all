# frozen_string_literal: true

# Phase 13: Stripe Webhooks Controller
# Multi-tenant subscription billing for Pharma Transport

module Stripe
  class WebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token

    def create
      payload = request.body.read
      sig_header = request.env["HTTP_STRIPE_SIGNATURE"]
      endpoint_secret = ENV.fetch("STRIPE_WEBHOOK_SECRET", nil)

      begin
        event = ::Stripe::Webhook.construct_event(
          payload, sig_header, endpoint_secret
        )
      rescue JSON::ParserError => e
        Rails.logger.error "[Stripe] Invalid payload: #{e.message}"
        return head :bad_request
      rescue ::Stripe::SignatureVerificationError => e
        Rails.logger.error "[Stripe] Invalid signature: #{e.message}"
        return head :bad_request
      end

      handle_event(event)
      head :ok
    end

    private

    def handle_event(event)
      Rails.logger.info "[Stripe] Received event: #{event.type}"

      case event.type
      when "checkout.session.completed"
        handle_checkout_session_completed(event.data.object)
      when "invoice.paid"
        handle_invoice_paid(event.data.object)
      when "customer.subscription.created"
        handle_subscription_created(event.data.object)
      when "customer.subscription.updated"
        handle_subscription_updated(event.data.object)
      when "customer.subscription.deleted"
        handle_subscription_deleted(event.data.object)
      else
        Rails.logger.info "[Stripe] Unhandled event type: #{event.type}"
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # CHECKOUT
    # ═══════════════════════════════════════════════════════════════════════════

    def handle_checkout_session_completed(session)
      tenant = find_tenant_from_metadata(session)
      return unless tenant

      tenant.update!(
        stripe_customer_id: session.customer,
        stripe_subscription_id: session.subscription,
        status: "active"
      )

      Rails.logger.info "[Stripe] Checkout completed for tenant #{tenant.id}"
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # INVOICES
    # ═══════════════════════════════════════════════════════════════════════════

    def handle_invoice_paid(invoice)
      tenant = Tenant.find_by(stripe_customer_id: invoice.customer)
      return unless tenant

      tenant.update!(
        status: "active",
        last_payment_at: Time.current
      )

      Rails.logger.info "[Stripe] Invoice paid for tenant #{tenant.id}: $#{invoice.amount_paid / 100.0}"
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # SUBSCRIPTIONS
    # ═══════════════════════════════════════════════════════════════════════════

    def handle_subscription_created(subscription)
      tenant = Tenant.find_by(stripe_customer_id: subscription.customer)
      return unless tenant

      plan_name = extract_plan_name(subscription)

      tenant.update!(
        stripe_subscription_id: subscription.id,
        plan: plan_name,
        status: subscription.status
      )

      Rails.logger.info "[Stripe] Subscription created for tenant #{tenant.id}: #{plan_name}"
    end

    def handle_subscription_updated(subscription)
      tenant = Tenant.find_by(stripe_customer_id: subscription.customer)
      return unless tenant

      plan_name = extract_plan_name(subscription)

      tenant.update!(
        plan: plan_name,
        status: subscription.status
      )

      Rails.logger.info "[Stripe] Subscription updated for tenant #{tenant.id}: #{subscription.status}"
    end

    def handle_subscription_deleted(subscription)
      tenant = Tenant.find_by(stripe_customer_id: subscription.customer)
      return unless tenant

      tenant.update!(
        stripe_subscription_id: nil,
        plan: "free",
        status: "canceled"
      )

      Rails.logger.info "[Stripe] Subscription deleted for tenant #{tenant.id}"
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # HELPERS
    # ═══════════════════════════════════════════════════════════════════════════

    def find_tenant_from_metadata(session)
      tenant_id = session.metadata&.tenant_id || session.client_reference_id
      return nil unless tenant_id

      Tenant.find_by(id: tenant_id)
    end

    def extract_plan_name(subscription)
      subscription.items.data.first&.price&.lookup_key ||
        subscription.items.data.first&.price&.nickname ||
        "standard"
    end
  end
end
