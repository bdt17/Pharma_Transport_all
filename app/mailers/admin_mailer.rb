# frozen_string_literal: true

# =============================================================================
# AdminMailer
# =============================================================================
# Sends critical system notifications to administrators
# FDA 21 CFR Part 11 Compliant - audit logs all admin notifications
#
# Usage:
#   AdminMailer.backup_alert(message, details).deliver_later
#   AdminMailer.audit_chain_alert(verification_result).deliver_later
#   AdminMailer.system_health_alert(health_report).deliver_later
# =============================================================================

class AdminMailer < ApplicationMailer
  default to: -> { admin_recipients }

  # ===========================================================================
  # BACKUP ALERTS
  # ===========================================================================
  def backup_alert(message, details = {})
    @message = message
    @details = details
    @timestamp = Time.current.utc.iso8601
    @severity = details[:severity] || "warning"

    log_admin_notification("backup_alert", message)

    mail(
      subject: "[#{@severity.upcase}] Pharma Transport - Backup Alert",
      template_name: "system_alert"
    )
  end

  # ===========================================================================
  # AUDIT CHAIN ALERTS
  # ===========================================================================
  def audit_chain_alert(verification_result)
    @result = verification_result
    @timestamp = Time.current.utc.iso8601
    @severity = verification_result[:valid] ? "info" : "critical"

    log_admin_notification("audit_chain_alert", "Chain verification: #{@result[:valid]}")

    mail(
      subject: "[#{@severity.upcase}] Pharma Transport - Audit Chain #{@result[:valid] ? 'Verified' : 'INTEGRITY FAILURE'}",
      template_name: "audit_chain_alert"
    )
  end

  # ===========================================================================
  # SYSTEM HEALTH ALERTS
  # ===========================================================================
  def system_health_alert(health_report)
    @report = health_report
    @timestamp = Time.current.utc.iso8601
    @failed_checks = health_report[:checks]&.select { |_k, v| v[:status] != "ok" } || {}
    @severity = @failed_checks.any? ? "warning" : "info"

    log_admin_notification("system_health_alert", "Health check: #{@failed_checks.keys.join(', ')}")

    mail(
      subject: "[#{@severity.upcase}] Pharma Transport - System Health Alert",
      template_name: "system_alert"
    )
  end

  # ===========================================================================
  # SECURITY ALERTS
  # ===========================================================================
  def security_alert(event_type, details = {})
    @event_type = event_type
    @details = details
    @timestamp = Time.current.utc.iso8601
    @severity = "critical"

    log_admin_notification("security_alert", event_type)

    mail(
      subject: "[CRITICAL] Pharma Transport - Security Alert: #{event_type}",
      template_name: "security_alert"
    )
  end

  # ===========================================================================
  # STRIPE ALERTS
  # ===========================================================================
  def stripe_webhook_failure(event_type, error_message, metadata = {})
    @event_type = event_type
    @error_message = error_message
    @metadata = metadata
    @timestamp = Time.current.utc.iso8601
    @severity = "error"

    log_admin_notification("stripe_webhook_failure", "#{event_type}: #{error_message}")

    mail(
      subject: "[ERROR] Pharma Transport - Stripe Webhook Failed: #{event_type}",
      template_name: "stripe_alert"
    )
  end

  # ===========================================================================
  # COMPLIANCE ALERTS
  # ===========================================================================
  def compliance_report(report_data)
    @report = report_data
    @timestamp = Time.current.utc.iso8601
    @period = report_data[:period] || "weekly"

    log_admin_notification("compliance_report", "#{@period} compliance report generated")

    mail(
      subject: "Pharma Transport - #{@period.titleize} Compliance Report",
      template_name: "compliance_report"
    )
  end

  # ===========================================================================
  # DAILY SUMMARY
  # ===========================================================================
  def daily_operations_summary(summary_data)
    @summary = summary_data
    @date = summary_data[:date] || Date.current.iso8601
    @timestamp = Time.current.utc.iso8601

    log_admin_notification("daily_summary", "Operations summary for #{@date}")

    mail(
      subject: "Pharma Transport - Daily Operations Summary (#{@date})",
      template_name: "daily_summary"
    )
  end

  private

  def admin_recipients
    # Primary: ENV configured admins
    # Fallback: All admin users in database
    ENV.fetch("ADMIN_EMAILS", nil)&.split(",")&.map(&:strip) ||
      User.where(admin: true).pluck(:email).presence ||
      ["admin@pharmatransport.io"]
  end

  def log_admin_notification(notification_type, message)
    AuditLogger.log(
      event_type: "admin.notification_sent",
      action: "Admin notification: #{notification_type}",
      metadata: {
        notification_type: notification_type,
        message: message,
        recipients: admin_recipients,
        timestamp: Time.current.utc.iso8601
      }
    ) rescue nil
  end
end
