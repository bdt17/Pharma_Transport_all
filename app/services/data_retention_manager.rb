# frozen_string_literal: true

# =============================================================================
# DataRetentionManager Service
# =============================================================================
# FDA 21 CFR Part 11 Compliant Data Retention Management
# Purges old logs according to compliance retention rules
#
# FDA Requirements:
#   - Audit logs: NEVER delete (immutable)
#   - Financial records: 7 years minimum
#   - System logs: 90 days minimum
#   - Session data: 30 days
#
# Usage:
#   DataRetentionManager.cleanup_all!
#   DataRetentionManager.cleanup_system_logs!
#   DataRetentionManager.retention_report
# =============================================================================

class DataRetentionManager
  # FDA 21 CFR Part 11 Retention Periods
  RETENTION_PERIODS = {
    audit_events: nil,           # Never delete - FDA requirement
    audit_logs: nil,             # Never delete - FDA requirement
    stripe_events: 2555,         # 7 years (financial records)
    paper_trail_versions: nil,   # Never delete - FDA requirement
    system_logs: 90,             # 90 days
    sessions: 30,                # 30 days
    temp_files: 7,               # 7 days
    job_logs: 30                 # 30 days
  }.freeze

  class << self
    # =========================================================================
    # MAIN CLEANUP
    # =========================================================================

    def cleanup_all!(dry_run: false)
      results = {
        timestamp: Time.current.utc.iso8601,
        dry_run: dry_run,
        cleanups: []
      }

      # System logs
      results[:cleanups] << cleanup_system_logs!(dry_run: dry_run)

      # Stripe events (keep 7 years for financial compliance)
      results[:cleanups] << cleanup_stripe_events!(dry_run: dry_run)

      # Session data
      results[:cleanups] << cleanup_sessions!(dry_run: dry_run)

      # Temporary files
      results[:cleanups] << cleanup_temp_files!(dry_run: dry_run)

      # Sidekiq dead jobs
      results[:cleanups] << cleanup_sidekiq_dead_jobs!(dry_run: dry_run)

      # Log the cleanup
      log_cleanup(results) unless dry_run

      Rails.logger.info "[DataRetention] Cleanup complete: #{results.to_json}"
      results
    end

    # =========================================================================
    # INDIVIDUAL CLEANUPS
    # =========================================================================

    def cleanup_system_logs!(dry_run: false)
      retention_days = RETENTION_PERIODS[:system_logs]
      cutoff_date = retention_days.days.ago

      count = SystemLog.where("created_at < ?", cutoff_date).count

      unless dry_run
        SystemLog.where("created_at < ?", cutoff_date).delete_all
      end

      {
        type: "system_logs",
        retention_days: retention_days,
        records_deleted: count,
        cutoff_date: cutoff_date.utc.iso8601
      }
    rescue StandardError => e
      { type: "system_logs", error: e.message }
    end

    def cleanup_stripe_events!(dry_run: false)
      retention_days = RETENTION_PERIODS[:stripe_events]
      cutoff_date = retention_days.days.ago

      # Only delete processed events older than retention period
      count = StripeEvent.where("processed_at < ?", cutoff_date)
                         .where(processing_status: "processed")
                         .count

      unless dry_run
        StripeEvent.where("processed_at < ?", cutoff_date)
                   .where(processing_status: "processed")
                   .delete_all
      end

      {
        type: "stripe_events",
        retention_days: retention_days,
        records_deleted: count,
        cutoff_date: cutoff_date.utc.iso8601
      }
    rescue StandardError => e
      { type: "stripe_events", error: e.message }
    end

    def cleanup_sessions!(dry_run: false)
      retention_days = RETENTION_PERIODS[:sessions]
      cutoff_date = retention_days.days.ago

      # If using database sessions
      count = 0
      if ActiveRecord::Base.connection.table_exists?(:sessions)
        count = ActiveRecord::Base.connection.execute(
          "SELECT COUNT(*) FROM sessions WHERE updated_at < '#{cutoff_date.to_s(:db)}'"
        ).first["count"].to_i

        unless dry_run
          ActiveRecord::Base.connection.execute(
            "DELETE FROM sessions WHERE updated_at < '#{cutoff_date.to_s(:db)}'"
          )
        end
      end

      {
        type: "sessions",
        retention_days: retention_days,
        records_deleted: count,
        cutoff_date: cutoff_date.utc.iso8601
      }
    rescue StandardError => e
      { type: "sessions", error: e.message }
    end

    def cleanup_temp_files!(dry_run: false)
      retention_days = RETENTION_PERIODS[:temp_files]
      cutoff_date = retention_days.days.ago

      temp_dir = Rails.root.join("tmp")
      files_deleted = 0

      Dir.glob(temp_dir.join("**/*")).each do |file|
        next if File.directory?(file)
        next if File.basename(file).start_with?(".")
        next unless File.mtime(file) < cutoff_date

        # Skip important files
        next if file.include?("pids")
        next if file.include?("cache")
        next if file.include?("sockets")

        files_deleted += 1
        File.delete(file) unless dry_run
      end

      {
        type: "temp_files",
        retention_days: retention_days,
        files_deleted: files_deleted,
        cutoff_date: cutoff_date.utc.iso8601
      }
    rescue StandardError => e
      { type: "temp_files", error: e.message }
    end

    def cleanup_sidekiq_dead_jobs!(dry_run: false)
      return { type: "sidekiq_dead_jobs", skipped: true } unless defined?(Sidekiq)

      retention_days = RETENTION_PERIODS[:job_logs]
      cutoff_timestamp = retention_days.days.ago.to_f

      dead_set = Sidekiq::DeadSet.new
      count = dead_set.select { |job| job.at.to_f < cutoff_timestamp }.count

      unless dry_run
        dead_set.each do |job|
          job.delete if job.at.to_f < cutoff_timestamp
        end
      end

      {
        type: "sidekiq_dead_jobs",
        retention_days: retention_days,
        jobs_deleted: count
      }
    rescue StandardError => e
      { type: "sidekiq_dead_jobs", error: e.message }
    end

    # =========================================================================
    # RETENTION REPORT
    # =========================================================================

    def retention_report
      {
        generated_at: Time.current.utc.iso8601,
        retention_policies: RETENTION_PERIODS,
        current_counts: current_record_counts,
        storage_usage: storage_usage_report,
        compliance_status: compliance_check
      }
    end

    def current_record_counts
      {
        audit_events: safe_count(AuditEvent),
        audit_logs: safe_count(AuditLog),
        stripe_events: safe_count(StripeEvent),
        paper_trail_versions: safe_count(PaperTrail::Version),
        system_logs: safe_count(SystemLog),
        tenants: safe_count(Tenant),
        users: safe_count(User)
      }
    end

    def storage_usage_report
      {
        audit_events_size: table_size("audit_events"),
        audit_logs_size: table_size("audit_logs"),
        stripe_events_size: table_size("stripe_events"),
        versions_size: table_size("versions"),
        total_database_size: database_size
      }
    rescue StandardError => e
      { error: e.message }
    end

    def compliance_check
      checks = []

      # Verify audit events are never deleted
      oldest_audit = AuditEvent.minimum(:created_at)
      if oldest_audit && oldest_audit > 1.year.ago
        checks << { check: "audit_history", status: "warning", message: "Less than 1 year of audit history" }
      else
        checks << { check: "audit_history", status: "ok" }
      end

      # Verify chain integrity
      chain_result = AuditEvent.verify_chain rescue { valid: false }
      checks << {
        check: "audit_chain_integrity",
        status: chain_result[:valid] ? "ok" : "failed",
        details: chain_result.slice(:checked, :first_sequence, :last_sequence)
      }

      # Verify no gaps in sequences
      gaps = find_sequence_gaps
      checks << {
        check: "sequence_continuity",
        status: gaps.empty? ? "ok" : "warning",
        gaps_found: gaps.count
      }

      {
        overall_status: checks.all? { |c| c[:status] == "ok" } ? "compliant" : "review_needed",
        checks: checks
      }
    end

    private

    # =========================================================================
    # HELPERS
    # =========================================================================

    def safe_count(model)
      model.count
    rescue StandardError
      "N/A"
    end

    def table_size(table_name)
      result = ActiveRecord::Base.connection.execute(
        "SELECT pg_size_pretty(pg_total_relation_size('#{table_name}'))"
      )
      result.first["pg_size_pretty"]
    rescue StandardError
      "N/A"
    end

    def database_size
      result = ActiveRecord::Base.connection.execute(
        "SELECT pg_size_pretty(pg_database_size(current_database()))"
      )
      result.first["pg_size_pretty"]
    rescue StandardError
      "N/A"
    end

    def find_sequence_gaps
      sequences = AuditEvent.order(:sequence).pluck(:sequence)
      gaps = []

      sequences.each_cons(2) do |a, b|
        gaps << { from: a, to: b } if b - a > 1
      end

      gaps
    end

    def log_cleanup(results)
      SystemLog.create!(
        log_type: "data_retention_cleanup",
        message: "Data retention cleanup completed",
        metadata: results,
        severity: "info"
      ) rescue nil

      AuditLogger.log(
        event_type: "system.data_retention_cleanup",
        action: "Scheduled data retention cleanup executed",
        metadata: {
          cleanups: results[:cleanups].map { |c| { type: c[:type], deleted: c[:records_deleted] || c[:files_deleted] || 0 } },
          timestamp: results[:timestamp]
        }
      ) rescue nil
    end
  end
end
