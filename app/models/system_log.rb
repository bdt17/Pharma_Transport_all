# frozen_string_literal: true

# =============================================================================
# SystemLog Model
# =============================================================================
# Records system-level events, job executions, and operational metrics
# FDA 21 CFR Part 11 Compliant - immutable audit trail for system operations
#
# Usage:
#   SystemLog.create!(log_type: "backup_completed", message: "Daily backup successful")
#   SystemLog.error!("stripe_webhook", "Signature verification failed", metadata: { event_id: "evt_123" })
#   SystemLog.info!("sidekiq_job", "SubscriptionSyncJob completed", metadata: { tenants_synced: 42 })
# =============================================================================

class SystemLog < ApplicationRecord
  # ===========================================================================
  # VALIDATIONS
  # ===========================================================================
  validates :log_type, presence: true
  validates :message, presence: true
  validates :severity, presence: true, inclusion: { in: %w[debug info warning error critical] }

  # ===========================================================================
  # SCOPES
  # ===========================================================================
  scope :recent, -> { order(created_at: :desc) }
  scope :by_severity, ->(severity) { where(severity: severity) }
  scope :by_type, ->(log_type) { where(log_type: log_type) }
  scope :errors_and_above, -> { where(severity: %w[error critical]) }
  scope :today, -> { where("created_at >= ?", Time.current.beginning_of_day) }
  scope :this_week, -> { where("created_at >= ?", 1.week.ago) }

  # ===========================================================================
  # CLASS METHODS - Convenience Logging
  # ===========================================================================
  class << self
    def debug!(log_type, message, metadata: {})
      create_log("debug", log_type, message, metadata)
    end

    def info!(log_type, message, metadata: {})
      create_log("info", log_type, message, metadata)
    end

    def warning!(log_type, message, metadata: {})
      create_log("warning", log_type, message, metadata)
    end

    def error!(log_type, message, metadata: {})
      create_log("error", log_type, message, metadata)
    end

    def critical!(log_type, message, metadata: {})
      create_log("critical", log_type, message, metadata)
    end

    # Log job execution
    def log_job(job_class, status:, duration_ms: nil, metadata: {})
      severity = status == "failed" ? "error" : "info"
      create_log(
        severity,
        "sidekiq_job",
        "#{job_class} #{status}",
        metadata.merge(
          job_class: job_class,
          status: status,
          duration_ms: duration_ms
        )
      )
    end

    # Log webhook processing
    def log_webhook(provider, event_type:, status:, metadata: {})
      severity = status == "failed" ? "error" : "info"
      create_log(
        severity,
        "#{provider}_webhook",
        "#{event_type} #{status}",
        metadata.merge(
          provider: provider,
          event_type: event_type,
          status: status
        )
      )
    end

    # Summary statistics
    def daily_summary
      today_logs = today
      {
        date: Date.current.iso8601,
        total_entries: today_logs.count,
        by_severity: today_logs.group(:severity).count,
        by_type: today_logs.group(:log_type).count,
        errors: today_logs.errors_and_above.count
      }
    end

    private

    def create_log(severity, log_type, message, metadata)
      create!(
        severity: severity,
        log_type: log_type,
        message: message,
        metadata: metadata,
        recorded_at: Time.current
      )
    rescue StandardError => e
      Rails.logger.error "[SystemLog] Failed to create log: #{e.message}"
      Rails.logger.error "  #{severity} | #{log_type} | #{message}"
      nil
    end
  end

  # ===========================================================================
  # INSTANCE METHODS
  # ===========================================================================
  def error?
    severity.in?(%w[error critical])
  end

  def critical?
    severity == "critical"
  end

  def as_json(options = {})
    super(options).merge(
      "recorded_at" => recorded_at&.utc&.iso8601,
      "created_at" => created_at&.utc&.iso8601
    )
  end
end
