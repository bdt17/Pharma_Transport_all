# frozen_string_literal: true

# =============================================================================
# AuditDigestJob
# =============================================================================
# Weekly audit digest generation and distribution
# FDA 21 CFR Part 11 Compliant - Includes SHA-256 signature for verification
#
# Schedule: Every Sunday at 8 AM UTC
# Usage: AuditDigestJob.perform_async
# =============================================================================

class AuditDigestJob
  include Sidekiq::Job

  sidekiq_options queue: :mailers, retry: 3

  # =========================================================================
  # MAIN ENTRY POINT
  # =========================================================================

  def perform(options = {})
    @digest_type = options["type"] || "weekly"
    @tenant_id = options["tenant_id"]
    @dry_run = options["dry_run"] || false

    Rails.logger.info "[AuditDigest] Starting #{@digest_type} digest generation"

    case @digest_type
    when "weekly"
      generate_weekly_digests
    when "admin"
      generate_admin_digest
    when "tenant"
      generate_tenant_digest(@tenant_id)
    when "integrity_check"
      perform_integrity_check
    end

    Rails.logger.info "[AuditDigest] Completed"
  end

  private

  # =========================================================================
  # WEEKLY DIGESTS
  # =========================================================================

  def generate_weekly_digests
    # Send admin summary
    generate_admin_digest

    # Send tenant-specific digests
    Tenant.active.where.not(billing_email: nil).find_each do |tenant|
      generate_tenant_digest(tenant.id)
    end
  end

  def generate_admin_digest
    return log_dry_run("admin_summary") if @dry_run

    AuditDigestMailer.admin_summary.deliver_later
    log_digest_sent("admin_summary", nil)
  end

  def generate_tenant_digest(tenant_id)
    tenant = Tenant.find_by(id: tenant_id)
    return unless tenant&.billing_email.present?
    return log_dry_run("tenant_digest", tenant) if @dry_run

    AuditDigestMailer.weekly_digest(tenant).deliver_later
    log_digest_sent("weekly_digest", tenant)
  end

  # =========================================================================
  # INTEGRITY CHECK
  # =========================================================================

  def perform_integrity_check
    verification = AuditEvent.verify_chain

    unless verification[:valid]
      handle_integrity_failure(verification)
    end

    store_verification_result(verification)
    verification
  end

  def handle_integrity_failure(verification)
    Rails.logger.error "[AuditDigest] CHAIN INTEGRITY FAILURE: #{verification[:errors].to_json}"

    return if @dry_run

    AuditDigestMailer.chain_integrity_alert(verification).deliver_now

    # Create critical system log
    SystemLog.create!(
      log_type: "audit_integrity_failure",
      message: "FDA audit chain integrity failure detected",
      metadata: verification,
      severity: "critical"
    ) rescue nil
  end

  def store_verification_result(verification)
    SystemLog.create!(
      log_type: "audit_verification",
      message: verification[:valid] ? "Audit chain verified" : "Audit chain verification failed",
      metadata: {
        valid: verification[:valid],
        checked: verification[:checked],
        first_sequence: verification[:first_sequence],
        last_sequence: verification[:last_sequence],
        errors_count: verification[:errors]&.count || 0,
        timestamp: Time.current.utc.iso8601
      },
      severity: verification[:valid] ? "info" : "critical"
    ) rescue nil
  end

  # =========================================================================
  # LOGGING
  # =========================================================================

  def log_digest_sent(type, tenant)
    Rails.logger.info "[AuditDigest] Sent #{type} to #{tenant&.subdomain || 'admins'}"

    AuditLogger.log(
      event_type: "system.audit_digest_sent",
      action: "Weekly audit digest sent",
      tenant: tenant,
      metadata: {
        digest_type: type,
        recipient: tenant&.billing_email || "admin",
        timestamp: Time.current.utc.iso8601
      }
    ) rescue nil
  end

  def log_dry_run(type, tenant = nil)
    Rails.logger.info "[AuditDigest] DRY RUN: Would send #{type} to #{tenant&.subdomain || 'admins'}"
  end
end
