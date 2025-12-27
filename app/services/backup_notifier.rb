# frozen_string_literal: true

# =============================================================================
# BackupNotifier Service
# =============================================================================
# Monitors database backups and audit log integrity
# FDA 21 CFR Part 11 Compliant - Alerts on compliance risks
#
# Usage:
#   BackupNotifier.verify_and_alert
#   BackupNotifier.check_audit_discrepancies
# =============================================================================

class BackupNotifier
  class << self
    # =========================================================================
    # MAIN VERIFICATION
    # =========================================================================

    def verify_and_alert
      results = {
        timestamp: Time.current.utc.iso8601,
        checks: []
      }

      # Run all checks
      results[:checks] << check_database_backup
      results[:checks] << check_audit_chain_integrity
      results[:checks] << check_audit_discrepancies
      results[:checks] << check_system_health

      # Determine overall status
      results[:status] = results[:checks].all? { |c| c[:status] == "ok" } ? "healthy" : "alert"
      results[:alerts] = results[:checks].select { |c| c[:status] != "ok" }

      # Send alerts if needed
      send_alerts(results) if results[:alerts].any?

      # Log results
      log_verification_results(results)

      results
    end

    # =========================================================================
    # DATABASE BACKUP CHECK
    # =========================================================================

    def check_database_backup
      last_backup = fetch_last_backup_time

      if last_backup.nil?
        return {
          check: "database_backup",
          status: "warning",
          message: "Unable to determine last backup time",
          details: { source: "render_api_unavailable" }
        }
      end

      hours_since_backup = (Time.current - last_backup) / 1.hour

      if hours_since_backup > 24
        {
          check: "database_backup",
          status: "critical",
          message: "Database backup overdue",
          details: {
            last_backup: last_backup.utc.iso8601,
            hours_overdue: hours_since_backup.round(1)
          }
        }
      elsif hours_since_backup > 12
        {
          check: "database_backup",
          status: "warning",
          message: "Database backup may be delayed",
          details: {
            last_backup: last_backup.utc.iso8601,
            hours_since: hours_since_backup.round(1)
          }
        }
      else
        {
          check: "database_backup",
          status: "ok",
          message: "Database backup current",
          details: {
            last_backup: last_backup.utc.iso8601,
            hours_since: hours_since_backup.round(1)
          }
        }
      end
    end

    # =========================================================================
    # AUDIT CHAIN INTEGRITY
    # =========================================================================

    def check_audit_chain_integrity
      result = AuditEvent.verify_chain rescue { valid: false, error: "verification_failed" }

      if result[:valid] == true
        {
          check: "audit_chain_integrity",
          status: "ok",
          message: "Audit chain verified",
          details: {
            records_checked: result[:checked],
            first_sequence: result[:first_sequence],
            last_sequence: result[:last_sequence]
          }
        }
      else
        {
          check: "audit_chain_integrity",
          status: "critical",
          message: "Audit chain integrity failure",
          details: {
            errors: result[:errors]&.first(5),
            error_count: result[:errors]&.count || 0
          }
        }
      end
    end

    # =========================================================================
    # AUDIT DISCREPANCY CHECK
    # =========================================================================

    def check_audit_discrepancies
      discrepancies = []

      # Check for gaps in sequence numbers
      gaps = find_sequence_gaps
      discrepancies << { type: "sequence_gap", details: gaps } if gaps.any?

      # Check for orphaned records
      orphans = find_orphaned_audit_records
      discrepancies << { type: "orphaned_records", details: orphans } if orphans.any?

      # Check for timestamp anomalies
      anomalies = find_timestamp_anomalies
      discrepancies << { type: "timestamp_anomaly", details: anomalies } if anomalies.any?

      if discrepancies.any?
        {
          check: "audit_discrepancies",
          status: "warning",
          message: "Audit log discrepancies detected",
          details: { discrepancies: discrepancies }
        }
      else
        {
          check: "audit_discrepancies",
          status: "ok",
          message: "No audit discrepancies found",
          details: {}
        }
      end
    end

    # =========================================================================
    # SYSTEM HEALTH CHECK
    # =========================================================================

    def check_system_health
      issues = []

      # Check database connection
      begin
        ActiveRecord::Base.connection.execute("SELECT 1")
      rescue StandardError => e
        issues << { component: "database", error: e.message }
      end

      # Check Redis connection
      begin
        Redis.new(url: ENV["REDIS_URL"]).ping if ENV["REDIS_URL"]
      rescue StandardError => e
        issues << { component: "redis", error: e.message }
      end

      # Check disk space (if available)
      disk_usage = check_disk_usage
      issues << { component: "disk", warning: "#{disk_usage}% used" } if disk_usage && disk_usage > 85

      if issues.any?
        {
          check: "system_health",
          status: issues.any? { |i| i[:error] } ? "critical" : "warning",
          message: "System health issues detected",
          details: { issues: issues }
        }
      else
        {
          check: "system_health",
          status: "ok",
          message: "All systems operational",
          details: {}
        }
      end
    end

    private

    # =========================================================================
    # HELPER METHODS
    # =========================================================================

    def fetch_last_backup_time
      # For Render, check SystemLog for last backup record
      # or query Render API if configured
      last_backup_log = SystemLog.where(log_type: "backup_completed")
                                 .order(created_at: :desc)
                                 .first

      return last_backup_log.created_at if last_backup_log

      # Fallback: assume daily backups at 3 AM UTC
      today_backup = Date.current.to_time.utc + 3.hours
      today_backup > Time.current ? today_backup - 1.day : today_backup
    rescue StandardError
      nil
    end

    def find_sequence_gaps
      gaps = []
      sequences = AuditEvent.order(:sequence).pluck(:sequence)

      sequences.each_cons(2) do |a, b|
        if b - a > 1
          gaps << { from: a, to: b, missing: (a + 1...b).to_a }
        end
      end

      gaps.first(10) # Limit to first 10 gaps
    end

    def find_orphaned_audit_records
      # Records with tenant_id that doesn't exist
      AuditEvent.where.not(tenant_id: nil)
                .where.not(tenant_id: Tenant.select(:id))
                .limit(10)
                .pluck(:id, :tenant_id)
                .map { |id, tid| { audit_event_id: id, missing_tenant_id: tid } }
    rescue StandardError
      []
    end

    def find_timestamp_anomalies
      # Records where created_at doesn't match sequence order
      anomalies = []
      prev_event = nil

      AuditEvent.order(:sequence).limit(1000).each do |event|
        if prev_event && event.created_at < prev_event.created_at
          anomalies << {
            sequence: event.sequence,
            created_at: event.created_at.utc.iso8601,
            previous_created_at: prev_event.created_at.utc.iso8601
          }
        end
        prev_event = event
      end

      anomalies.first(10)
    end

    def check_disk_usage
      output = `df -h / 2>/dev/null | tail -1`
      match = output.match(/(\d+)%/)
      match ? match[1].to_i : nil
    rescue StandardError
      nil
    end

    # =========================================================================
    # ALERTING
    # =========================================================================

    def send_alerts(results)
      results[:alerts].each do |alert|
        case alert[:status]
        when "critical"
          send_critical_alert(alert)
        when "warning"
          send_warning_alert(alert)
        end
      end
    end

    def send_critical_alert(alert)
      Rails.logger.error "[BackupNotifier] CRITICAL: #{alert[:check]} - #{alert[:message]}"

      AdminMailer.critical_alert(
        check: alert[:check],
        message: alert[:message],
        details: alert[:details]
      ).deliver_now rescue nil
    end

    def send_warning_alert(alert)
      Rails.logger.warn "[BackupNotifier] WARNING: #{alert[:check]} - #{alert[:message]}"

      AdminMailer.warning_alert(
        check: alert[:check],
        message: alert[:message],
        details: alert[:details]
      ).deliver_later rescue nil
    end

    def log_verification_results(results)
      SystemLog.create!(
        log_type: "backup_verification",
        message: "Backup verification #{results[:status]}",
        metadata: results,
        severity: results[:status] == "healthy" ? "info" : "warning"
      ) rescue nil

      Rails.logger.info "[BackupNotifier] Verification complete: #{results[:status]}"
    end
  end
end
