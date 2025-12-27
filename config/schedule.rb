# frozen_string_literal: true

# =============================================================================
# Sidekiq-Cron Schedule Configuration
# =============================================================================
# FDA 21 CFR Part 11 Compliant Scheduled Jobs
#
# Setup: Add sidekiq-cron to Gemfile, then configure in initializer
# Alternative: Use whenever gem with `whenever --update-crontab`
# =============================================================================

# For sidekiq-cron, configure in config/initializers/sidekiq.rb:
#
# Sidekiq.configure_server do |config|
#   config.on(:startup) do
#     schedule = YAML.load_file(Rails.root.join("config", "schedule.yml"))
#     Sidekiq::Cron::Job.load_from_hash(schedule)
#   end
# end

# =============================================================================
# SCHEDULE DEFINITIONS (for sidekiq-cron YAML format)
# =============================================================================
# Save this as config/schedule.yml for sidekiq-cron:
#
# subscription_sync:
#   cron: "0 3 * * *"
#   class: "SubscriptionSyncJob"
#   queue: critical
#   description: "Nightly Stripe subscription sync"
#
# audit_chain_verification:
#   cron: "0 6 * * *"
#   class: "AuditDigestJob"
#   args:
#     type: "integrity_check"
#   queue: critical
#   description: "Daily FDA audit chain verification"
#
# weekly_audit_digest:
#   cron: "0 8 * * 0"
#   class: "AuditDigestJob"
#   args:
#     type: "weekly"
#   queue: mailers
#   description: "Weekly audit digest emails"
#
# data_retention_cleanup:
#   cron: "0 4 * * 0"
#   class: "DataRetentionJob"
#   queue: low
#   description: "Weekly data retention cleanup"
#
# backup_verification:
#   cron: "0 7 * * *"
#   class: "BackupVerificationJob"
#   queue: low
#   description: "Daily backup verification"

# =============================================================================
# WHENEVER GEM CONFIGURATION (alternative)
# =============================================================================
# If using the whenever gem instead of sidekiq-cron:

set :output, "log/cron.log"
set :environment, ENV.fetch("RAILS_ENV", "production")

# Nightly Stripe sync (3 AM UTC)
every 1.day, at: "3:00 am" do
  runner "SubscriptionSyncJob.perform_async"
end

# Daily FDA audit chain verification (6 AM UTC)
every 1.day, at: "6:00 am" do
  rake "fda:verify_audit_chain"
end

# Weekly audit digest (Sunday 8 AM UTC)
every :sunday, at: "8:00 am" do
  runner "AuditDigestJob.perform_async('type' => 'weekly')"
end

# Weekly data retention cleanup (Sunday 4 AM UTC)
every :sunday, at: "4:00 am" do
  runner "DataRetentionManager.cleanup_all!"
end

# Daily backup verification (7 AM UTC)
every 1.day, at: "7:00 am" do
  runner "BackupNotifier.verify_and_alert"
end

# Hourly system health check
every 1.hour do
  runner "SystemHealthChecker.perform_check"
end

# Monthly MRR report (1st of month, 9 AM UTC)
every "0 9 1 * *" do
  runner "SubscriptionReporter.monthly_report.tap { |r| AdminMailer.mrr_report(r).deliver_later }"
end
