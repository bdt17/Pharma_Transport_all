# frozen_string_literal: true

# =============================================================================
# AuditLogger Service
# =============================================================================
# FDA 21 CFR Part 11 compliant audit logging service
# Automatically records subscription state changes and admin billing actions
#
# Usage:
#   AuditLogger.subscription_created(tenant: tenant, user: user)
#   AuditLogger.payment_failed(tenant: tenant, invoice: invoice)
#   AuditLogger.admin_action(tenant: tenant, user: admin, action: "suspended")
#
# Deploy: Render + PostgreSQL
# =============================================================================

class AuditLogger
  class << self
    # =========================================================================
    # SUBSCRIPTION EVENTS
    # =========================================================================

    def subscription_created(tenant:, user: nil, plan: nil, metadata: {})
      record_event(
        event_type: "subscription.created",
        action: "Subscription created for plan: #{plan || tenant.plan}",
        tenant: tenant,
        user: user,
        resource: tenant,
        changes: {
          plan: { from: nil, to: plan || tenant.plan },
          status: { from: nil, to: "active" }
        },
        metadata: metadata
      )
    end

    def subscription_activated(tenant:, user: nil, previous_status: nil, metadata: {})
      record_event(
        event_type: "subscription.activated",
        action: "Subscription activated",
        tenant: tenant,
        user: user,
        resource: tenant,
        changes: {
          subscription_status: { from: previous_status, to: "active" }
        },
        metadata: metadata
      )
    end

    def subscription_updated(tenant:, user: nil, previous_plan: nil, new_plan: nil, metadata: {})
      record_event(
        event_type: "subscription.updated",
        action: "Subscription plan changed from #{previous_plan} to #{new_plan}",
        tenant: tenant,
        user: user,
        resource: tenant,
        changes: {
          plan: { from: previous_plan, to: new_plan }
        },
        metadata: metadata
      )
    end

    def subscription_canceled(tenant:, user: nil, reason: nil, metadata: {})
      record_event(
        event_type: "subscription.canceled",
        action: "Subscription canceled#{reason ? ": #{reason}" : ""}",
        tenant: tenant,
        user: user,
        resource: tenant,
        changes: {
          subscription_status: { from: tenant.subscription_status, to: "canceled" },
          plan: { from: tenant.plan, to: "free" }
        },
        metadata: metadata.merge(cancellation_reason: reason)
      )
    end

    # =========================================================================
    # BILLING EVENTS
    # =========================================================================

    def checkout_started(tenant:, user: nil, plan: nil, session_id: nil, metadata: {})
      record_event(
        event_type: "billing.checkout_started",
        action: "Checkout session started for plan: #{plan}",
        tenant: tenant,
        user: user,
        resource: tenant,
        changes: {},
        metadata: metadata.merge(
          plan: plan,
          stripe_session_id: session_id
        )
      )
    end

    def checkout_completed(tenant:, session_id: nil, amount: nil, metadata: {})
      record_event(
        event_type: "billing.checkout_completed",
        action: "Checkout completed successfully",
        tenant: tenant,
        user: nil,
        resource: tenant,
        changes: {
          subscription_status: { from: tenant.subscription_status, to: "active" }
        },
        metadata: metadata.merge(
          stripe_session_id: session_id,
          amount: amount
        )
      )
    end

    def payment_succeeded(tenant:, invoice_id: nil, amount: nil, metadata: {})
      record_event(
        event_type: "billing.payment_succeeded",
        action: "Payment of #{format_amount(amount)} processed successfully",
        tenant: tenant,
        user: nil,
        resource: tenant,
        changes: {
          subscription_status: { from: tenant.subscription_status, to: "active" }
        },
        metadata: metadata.merge(
          stripe_invoice_id: invoice_id,
          amount: amount
        )
      )
    end

    def payment_failed(tenant:, invoice_id: nil, amount: nil, attempt: nil, reason: nil, metadata: {})
      record_event(
        event_type: "billing.payment_failed",
        action: "Payment of #{format_amount(amount)} failed (attempt #{attempt})",
        tenant: tenant,
        user: nil,
        resource: tenant,
        changes: {
          subscription_status: { from: tenant.subscription_status, to: "past_due" }
        },
        metadata: metadata.merge(
          stripe_invoice_id: invoice_id,
          amount: amount,
          attempt_count: attempt,
          failure_reason: reason
        )
      )
    end

    # =========================================================================
    # ADMIN EVENTS
    # =========================================================================

    def admin_action(tenant:, user:, action:, resource: nil, changes: {}, metadata: {})
      record_event(
        event_type: "admin.#{action.to_s.underscore}",
        action: "Admin action: #{action}",
        tenant: tenant,
        user: user,
        resource: resource || tenant,
        changes: changes,
        metadata: metadata.merge(admin_user_id: user&.id)
      )
    end

    def tenant_suspended(tenant:, user:, reason: nil, metadata: {})
      record_event(
        event_type: "admin.tenant_suspended",
        action: "Tenant account suspended#{reason ? ": #{reason}" : ""}",
        tenant: tenant,
        user: user,
        resource: tenant,
        changes: {
          status: { from: tenant.status, to: "suspended" }
        },
        metadata: metadata.merge(suspension_reason: reason)
      )
    end

    def api_key_created(tenant:, user:, api_key:, metadata: {})
      record_event(
        event_type: "admin.api_key_created",
        action: "API key created: #{api_key.name}",
        tenant: tenant,
        user: user,
        resource: api_key,
        changes: {},
        metadata: metadata.merge(
          api_key_id: api_key.id,
          api_key_name: api_key.name
        )
      )
    end

    def api_key_revoked(tenant:, user:, api_key:, metadata: {})
      record_event(
        event_type: "admin.api_key_revoked",
        action: "API key revoked: #{api_key.name}",
        tenant: tenant,
        user: user,
        resource: api_key,
        changes: {
          active: { from: true, to: false }
        },
        metadata: metadata.merge(
          api_key_id: api_key.id,
          api_key_name: api_key.name
        )
      )
    end

    # =========================================================================
    # ACCESS EVENTS
    # =========================================================================

    def access_denied(tenant:, user: nil, reason: nil, path: nil, metadata: {})
      record_event(
        event_type: "access.denied",
        action: "Access denied: #{reason || 'subscription required'}",
        tenant: tenant,
        user: user,
        resource: tenant,
        changes: {},
        metadata: metadata.merge(
          denial_reason: reason,
          requested_path: path
        )
      )
    end

    def user_login(tenant:, user:, metadata: {})
      record_event(
        event_type: "access.login",
        action: "User logged in: #{user.email}",
        tenant: tenant,
        user: user,
        resource: user,
        changes: {},
        metadata: metadata
      )
    end

    # =========================================================================
    # GENERIC LOGGING
    # =========================================================================

    def log(event_type:, action:, tenant: nil, user: nil, resource: nil, changes: {}, metadata: {})
      record_event(
        event_type: event_type,
        action: action,
        tenant: tenant,
        user: user,
        resource: resource,
        changes: changes,
        metadata: metadata
      )
    end

    private

    # =========================================================================
    # INTERNAL
    # =========================================================================

    def record_event(event_type:, action:, tenant:, user:, resource:, changes:, metadata:)
      # Add standard metadata
      full_metadata = metadata.merge(
        timestamp: Time.current.utc.iso8601,
        environment: Rails.env,
        service: "audit_logger"
      )

      # Record to AuditEvent (FDA compliant with hash chain)
      AuditEvent.record!(
        event_type: event_type,
        action: action,
        tenant: tenant,
        user: user,
        resource: resource,
        changes: changes,
        metadata: full_metadata
      )

      # Also log to Rails logger for operational visibility
      Rails.logger.info "[AuditLogger] #{event_type} | tenant=#{tenant&.id} | user=#{user&.id} | #{action}"

      true
    rescue StandardError => e
      # Never fail the calling operation due to audit logging errors
      Rails.logger.error "[AuditLogger] Failed to record event: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      false
    end

    def format_amount(cents)
      return "N/A" unless cents
      "$#{'%.2f' % (cents.to_f / 100)}"
    end
  end
end
