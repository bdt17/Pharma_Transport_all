# frozen_string_literal: true

# =============================================================================
# AuditDigestMailer
# =============================================================================
# FDA 21 CFR Part 11 Compliant Weekly Audit Digest
# Sends immutable digest with SHA-256 signature for compliance verification
#
# Usage:
#   AuditDigestMailer.weekly_digest(tenant).deliver_later
#   AuditDigestMailer.admin_summary.deliver_later
# =============================================================================

class AuditDigestMailer < ApplicationMailer
  default from: "compliance@pharmatransport.io"
  layout "mailer"

  # =========================================================================
  # WEEKLY DIGEST FOR TENANT
  # =========================================================================

  def weekly_digest(tenant)
    @tenant = tenant
    @period_start = 1.week.ago.beginning_of_day
    @period_end = Time.current.end_of_day

    @audit_events = AuditEvent.for_tenant(tenant.id)
                              .in_range(@period_start, @period_end)
                              .order(:sequence)

    @stats = calculate_tenant_stats(@audit_events)
    @chain_verification = AuditEvent.verify_chain(tenant_id: tenant.id)
    @digest_signature = generate_digest_signature

    mail(
      to: tenant.billing_email || "admin@#{tenant.subdomain}.pharmatransport.io",
      subject: "[FDA Compliance] Weekly Audit Digest - #{@period_start.strftime('%B %d')} to #{@period_end.strftime('%B %d, %Y')}"
    )
  end

  # =========================================================================
  # ADMIN SUMMARY (ALL TENANTS)
  # =========================================================================

  def admin_summary(recipients = nil)
    @recipients = recipients || admin_email_list
    @period_start = 1.week.ago.beginning_of_day
    @period_end = Time.current.end_of_day

    @audit_events = AuditEvent.in_range(@period_start, @period_end).order(:sequence)
    @tenant_stats = calculate_all_tenant_stats
    @global_chain_verification = AuditEvent.verify_chain
    @mrr_report = SubscriptionReporter.mrr_breakdown
    @digest_signature = generate_admin_digest_signature

    mail(
      to: @recipients,
      subject: "[FDA Compliance] Weekly Admin Audit Summary - #{Date.current.strftime('%B %d, %Y')}"
    )
  end

  # =========================================================================
  # CHAIN INTEGRITY ALERT
  # =========================================================================

  def chain_integrity_alert(verification_result)
    @result = verification_result
    @timestamp = Time.current.utc.iso8601
    @affected_sequences = verification_result[:errors]&.map { |e| e[:sequence] } || []

    mail(
      to: admin_email_list,
      subject: "[CRITICAL] FDA Audit Chain Integrity Failure Detected",
      importance: "high"
    )
  end

  # =========================================================================
  # SUBSCRIPTION EVENT NOTIFICATION
  # =========================================================================

  def subscription_event_notification(tenant, event_type, details = {})
    @tenant = tenant
    @event_type = event_type
    @details = details
    @timestamp = Time.current.utc.iso8601

    subject = case event_type
              when "activated" then "Subscription Activated"
              when "canceled" then "Subscription Cancelled"
              when "payment_failed" then "Payment Failed - Action Required"
              when "plan_changed" then "Plan Changed"
              else "Subscription Update"
              end

    mail(
      to: tenant.billing_email,
      subject: "[PharmaTransport] #{subject}"
    )
  end

  private

  # =========================================================================
  # STATS CALCULATION
  # =========================================================================

  def calculate_tenant_stats(events)
    {
      total_events: events.count,
      billing_events: events.billing_events.count,
      subscription_events: events.subscription_events.count,
      admin_events: events.admin_events.count,
      access_events: events.where("event_type LIKE ?", "access.%").count,
      unique_users: events.distinct.count(:user_id),
      first_sequence: events.minimum(:sequence),
      last_sequence: events.maximum(:sequence)
    }
  end

  def calculate_all_tenant_stats
    Tenant.active.map do |tenant|
      events = AuditEvent.for_tenant(tenant.id).in_range(@period_start, @period_end)
      {
        tenant_id: tenant.id,
        subdomain: tenant.subdomain,
        plan: tenant.plan,
        event_count: events.count,
        subscription_status: tenant.subscription_status
      }
    end
  end

  # =========================================================================
  # SIGNATURE GENERATION
  # =========================================================================

  def generate_digest_signature
    data = [
      @tenant.id,
      @period_start.utc.iso8601,
      @period_end.utc.iso8601,
      @audit_events.count,
      @audit_events.first&.signature_hash,
      @audit_events.last&.signature_hash,
      @chain_verification[:valid]
    ].join("|")

    Digest::SHA256.hexdigest(data)
  end

  def generate_admin_digest_signature
    data = [
      "admin_digest",
      @period_start.utc.iso8601,
      @period_end.utc.iso8601,
      @audit_events.count,
      @global_chain_verification[:valid],
      @mrr_report[:total_mrr_cents]
    ].join("|")

    Digest::SHA256.hexdigest(data)
  end

  def admin_email_list
    ENV.fetch("ADMIN_EMAILS", "admin@pharmatransport.io").split(",").map(&:strip)
  end
end
