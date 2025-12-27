# frozen_string_literal: true

# =============================================================================
# Test Webhooks Rake Tasks
# =============================================================================
# Simulate Stripe webhook payloads for local development and testing
# NEVER use in production - test mode only
#
# Usage:
#   rails webhooks:test_checkout[tenant_id]
#   rails webhooks:test_payment_success[tenant_id]
#   rails webhooks:test_payment_failed[tenant_id]
#   rails webhooks:test_subscription_cancelled[tenant_id]
# =============================================================================

namespace :webhooks do
  desc "Test checkout.session.completed webhook"
  task :test_checkout, [:tenant_id] => :environment do |_t, args|
    verify_not_production!

    tenant = find_tenant(args[:tenant_id])
    event = build_checkout_completed_event(tenant)

    puts "[Webhook Test] Simulating checkout.session.completed for tenant #{tenant.id}"
    process_webhook_event(event)
  end

  desc "Test invoice.paid webhook"
  task :test_payment_success, [:tenant_id] => :environment do |_t, args|
    verify_not_production!

    tenant = find_tenant(args[:tenant_id])
    event = build_invoice_paid_event(tenant)

    puts "[Webhook Test] Simulating invoice.paid for tenant #{tenant.id}"
    process_webhook_event(event)
  end

  desc "Test invoice.payment_failed webhook"
  task :test_payment_failed, [:tenant_id, :attempt] => :environment do |_t, args|
    verify_not_production!

    tenant = find_tenant(args[:tenant_id])
    attempt = (args[:attempt] || 1).to_i
    event = build_invoice_payment_failed_event(tenant, attempt)

    puts "[Webhook Test] Simulating invoice.payment_failed (attempt #{attempt}) for tenant #{tenant.id}"
    process_webhook_event(event)
  end

  desc "Test customer.subscription.deleted webhook"
  task :test_subscription_cancelled, [:tenant_id] => :environment do |_t, args|
    verify_not_production!

    tenant = find_tenant(args[:tenant_id])
    event = build_subscription_deleted_event(tenant)

    puts "[Webhook Test] Simulating customer.subscription.deleted for tenant #{tenant.id}"
    process_webhook_event(event)
  end

  desc "Test customer.subscription.updated webhook"
  task :test_subscription_updated, [:tenant_id, :new_plan] => :environment do |_t, args|
    verify_not_production!

    tenant = find_tenant(args[:tenant_id])
    new_plan = args[:new_plan] || "enterprise"
    event = build_subscription_updated_event(tenant, new_plan)

    puts "[Webhook Test] Simulating subscription update to #{new_plan} for tenant #{tenant.id}"
    process_webhook_event(event)
  end

  desc "Send test webhook to local server"
  task :send_local, [:event_type, :tenant_id] => :environment do |_t, args|
    verify_not_production!

    tenant = find_tenant(args[:tenant_id])
    event_type = args[:event_type] || "checkout.session.completed"

    event = case event_type
            when "checkout.session.completed"
              build_checkout_completed_event(tenant)
            when "invoice.paid"
              build_invoice_paid_event(tenant)
            when "invoice.payment_failed"
              build_invoice_payment_failed_event(tenant, 1)
            when "customer.subscription.deleted"
              build_subscription_deleted_event(tenant)
            else
              raise "Unknown event type: #{event_type}"
            end

    puts "[Webhook Test] Sending #{event_type} to local server..."

    require "net/http"
    uri = URI("http://localhost:3000/stripe/webhooks")

    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new(uri.path)
    request.body = event.to_json
    request["Content-Type"] = "application/json"
    request["Stripe-Signature"] = generate_test_signature(request.body)

    response = http.request(request)

    puts "[Webhook Test] Response: #{response.code} #{response.message}"
    puts response.body if response.body.present?
  end

  desc "List available webhook test events"
  task list: :environment do
    puts ""
    puts "Available webhook test commands:"
    puts ""
    puts "  rails webhooks:test_checkout[TENANT_ID]"
    puts "    - Simulates successful Stripe Checkout"
    puts ""
    puts "  rails webhooks:test_payment_success[TENANT_ID]"
    puts "    - Simulates successful payment"
    puts ""
    puts "  rails webhooks:test_payment_failed[TENANT_ID,ATTEMPT]"
    puts "    - Simulates failed payment (ATTEMPT: 1, 2, or 3)"
    puts ""
    puts "  rails webhooks:test_subscription_cancelled[TENANT_ID]"
    puts "    - Simulates subscription cancellation"
    puts ""
    puts "  rails webhooks:test_subscription_updated[TENANT_ID,NEW_PLAN]"
    puts "    - Simulates plan change (NEW_PLAN: smb, enterprise)"
    puts ""
    puts "  rails webhooks:send_local[EVENT_TYPE,TENANT_ID]"
    puts "    - Sends actual HTTP request to localhost:3000"
    puts ""
  end

  # ===========================================================================
  # HELPER METHODS
  # ===========================================================================

  def verify_not_production!
    if Rails.env.production?
      puts "[Webhook Test] ERROR: Cannot run webhook tests in production"
      exit 1
    end
  end

  def find_tenant(tenant_id)
    if tenant_id.present?
      Tenant.find(tenant_id)
    else
      Tenant.first || raise("No tenants found. Create a tenant first.")
    end
  end

  def process_webhook_event(event)
    # Create a mock request
    controller = Stripe::WebhooksController.new
    controller.instance_variable_set(:@event, event)

    # Process directly
    case event.type
    when "checkout.session.completed"
      controller.send(:handle_checkout_completed, event)
    when "invoice.paid"
      controller.send(:handle_invoice_paid, event)
    when "invoice.payment_failed"
      controller.send(:handle_invoice_payment_failed, event)
    when "customer.subscription.deleted"
      controller.send(:handle_subscription_deleted, event)
    when "customer.subscription.updated"
      controller.send(:handle_subscription_updated, event)
    end

    puts "[Webhook Test] Event processed successfully"
  rescue StandardError => e
    puts "[Webhook Test] Error: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end

  # ===========================================================================
  # EVENT BUILDERS
  # ===========================================================================

  def build_checkout_completed_event(tenant)
    Stripe::Event.construct_from({
      id: "evt_test_#{SecureRandom.hex(8)}",
      type: "checkout.session.completed",
      livemode: false,
      api_version: "2024-12-18.acacia",
      created: Time.current.to_i,
      data: {
        object: {
          id: "cs_test_#{SecureRandom.hex(8)}",
          object: "checkout.session",
          customer: tenant.stripe_customer_id || "cus_test_#{SecureRandom.hex(8)}",
          subscription: "sub_test_#{SecureRandom.hex(8)}",
          amount_total: 29900,
          currency: "usd",
          metadata: {
            tenant_id: tenant.id.to_s,
            plan: "smb"
          },
          client_reference_id: tenant.id.to_s
        }
      }
    })
  end

  def build_invoice_paid_event(tenant)
    Stripe::Event.construct_from({
      id: "evt_test_#{SecureRandom.hex(8)}",
      type: "invoice.paid",
      livemode: false,
      api_version: "2024-12-18.acacia",
      created: Time.current.to_i,
      data: {
        object: {
          id: "in_test_#{SecureRandom.hex(8)}",
          object: "invoice",
          customer: tenant.stripe_customer_id || "cus_test_#{SecureRandom.hex(8)}",
          subscription: tenant.stripe_subscription_id || "sub_test_#{SecureRandom.hex(8)}",
          amount_paid: 29900,
          currency: "usd",
          billing_reason: "subscription_cycle"
        }
      }
    })
  end

  def build_invoice_payment_failed_event(tenant, attempt)
    Stripe::Event.construct_from({
      id: "evt_test_#{SecureRandom.hex(8)}",
      type: "invoice.payment_failed",
      livemode: false,
      api_version: "2024-12-18.acacia",
      created: Time.current.to_i,
      data: {
        object: {
          id: "in_test_#{SecureRandom.hex(8)}",
          object: "invoice",
          customer: tenant.stripe_customer_id || "cus_test_#{SecureRandom.hex(8)}",
          subscription: tenant.stripe_subscription_id || "sub_test_#{SecureRandom.hex(8)}",
          amount_due: 29900,
          currency: "usd",
          attempt_count: attempt,
          next_payment_attempt: (Time.current + 3.days).to_i
        }
      }
    })
  end

  def build_subscription_deleted_event(tenant)
    Stripe::Event.construct_from({
      id: "evt_test_#{SecureRandom.hex(8)}",
      type: "customer.subscription.deleted",
      livemode: false,
      api_version: "2024-12-18.acacia",
      created: Time.current.to_i,
      data: {
        object: {
          id: tenant.stripe_subscription_id || "sub_test_#{SecureRandom.hex(8)}",
          object: "subscription",
          customer: tenant.stripe_customer_id || "cus_test_#{SecureRandom.hex(8)}",
          status: "canceled",
          canceled_at: Time.current.to_i,
          cancellation_details: {
            reason: "cancellation_requested"
          }
        }
      }
    })
  end

  def build_subscription_updated_event(tenant, new_plan)
    price_id = Tenant::PLANS[new_plan]&.dig(:price_id) || "price_test"

    Stripe::Event.construct_from({
      id: "evt_test_#{SecureRandom.hex(8)}",
      type: "customer.subscription.updated",
      livemode: false,
      api_version: "2024-12-18.acacia",
      created: Time.current.to_i,
      data: {
        object: {
          id: tenant.stripe_subscription_id || "sub_test_#{SecureRandom.hex(8)}",
          object: "subscription",
          customer: tenant.stripe_customer_id || "cus_test_#{SecureRandom.hex(8)}",
          status: "active",
          current_period_end: (Time.current + 1.month).to_i,
          items: {
            data: [{
              price: {
                id: price_id,
                lookup_key: new_plan,
                nickname: new_plan.titleize
              }
            }]
          }
        },
        previous_attributes: {
          items: {}
        }
      }
    })
  end

  def generate_test_signature(payload)
    timestamp = Time.current.to_i
    secret = ENV.fetch("STRIPE_WEBHOOK_SECRET", "whsec_test_secret")
    signed_payload = "#{timestamp}.#{payload}"
    signature = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
    "t=#{timestamp},v1=#{signature}"
  end
end
