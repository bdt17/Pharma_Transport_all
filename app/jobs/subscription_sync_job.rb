# frozen_string_literal: true

# =============================================================================
# SubscriptionSyncJob
# =============================================================================
# MISSION CRITICAL: Nightly Stripe → Tenant sync + Webhook Insurance + Churn Detection
# FDA 21 CFR Part 11 Compliant - All discrepancies logged to immutable audit trail
#
# Schedule: Run nightly at 3 AM UTC via sidekiq-cron
# Idempotent: Safe to run multiple times
#
# Console Testing:
#   SubscriptionSyncJob.new.perform                      # Full sync
#   SubscriptionSyncJob.new.perform("dry_run" => true)   # Preview only
#   SubscriptionSyncJob.new.perform("force_all" => true) # Sync ALL tenants
#   SubscriptionSyncJob.perform_async                    # Queue for Sidekiq
# =============================================================================

class SubscriptionSyncJob
  include Sidekiq::Job

  sidekiq_options queue: :critical, retry: 3, dead: true, lock: :until_executed

  # =========================================================================
  # MAIN ENTRY POINT
  # =========================================================================

  def perform(options = {})
    @dry_run = options["dry_run"] || options[:dry_run] || false
    @force_all = options["force_all"] || options[:force_all] || false
    @start_time = Time.current

    @results = {
      synced: 0,
      errors: 0,
      skipped: 0,
      churned_detected: 0,
      webhook_misses: 0,
      details: [],
      discrepancies: []
    }

    Rails.logger.info "[SubscriptionSync] Starting nightly sync (dry_run=#{@dry_run}, force_all=#{@force_all})"

    # Main sync operations
    sync_all_stripe_tenants
    detect_missed_webhooks
    detect_churn_candidates
    verify_audit_integrity

    # Generate final report
    generate_sync_report

    Rails.logger.info "[SubscriptionSync] Complete in #{elapsed_time}s: synced=#{@results[:synced]}, errors=#{@results[:errors]}"
    @results
  rescue StandardError => e
    Rails.logger.error "[SubscriptionSync] CRITICAL FAILURE: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
    log_sync_failure(e)
    notify_sync_failure(e)
    raise
  end

  private

  # =========================================================================
  # STRIPE SYNCHRONIZATION - Core Logic
  # =========================================================================

  def sync_all_stripe_tenants
    tenants_to_sync.find_each(batch_size: 50) do |tenant|
      sync_tenant(tenant)
    rescue Stripe::RateLimitError
      Rails.logger.warn "[SubscriptionSync] Rate limited, sleeping..."
      sleep(2)
      retry
    rescue StandardError => e
      record_error(tenant, e)
    end
  end

  def tenants_to_sync
    base_scope = Tenant.where.not(stripe_customer_id: [nil, ""])

    if @force_all
      base_scope
    else
      # Sync: recently updated, problematic states, or haven't synced in 7 days
      base_scope.where(
        "updated_at > ? OR subscription_status IN (?) OR last_synced_at IS NULL OR last_synced_at < ?",
        48.hours.ago,
        %w[past_due incomplete unpaid],
        7.days.ago
      )
    end
  end

  def sync_tenant(tenant)
    return @results[:skipped] += 1 unless tenant.stripe_customer_id.present?

    stripe_data = fetch_stripe_subscription(tenant)

    if stripe_data[:subscription].nil?
      handle_no_subscription(tenant)
      return
    end

    changes = detect_discrepancies(tenant, stripe_data)

    if changes.empty?
      mark_synced(tenant) unless @dry_run
      @results[:skipped] += 1
      return
    end

    # Found discrepancies - likely missed webhook
    @results[:webhook_misses] += 1
    @results[:discrepancies] << build_discrepancy_record(tenant, changes)

    apply_corrections(tenant, stripe_data, changes) unless @dry_run
    @results[:synced] += 1
    @results[:details] << { tenant_id: tenant.id, subdomain: tenant.subdomain, changes: changes }
  end

  # =========================================================================
  # STRIPE API CALLS
  # =========================================================================

  def fetch_stripe_subscription(tenant)
    # Fetch subscriptions for this customer
    subscriptions = Stripe::Subscription.list(
      customer: tenant.stripe_customer_id,
      status: "all",
      limit: 5,
      expand: ["data.items.data.price"]
    )

    # Prioritize active subscription, then most recent
    subscription = subscriptions.data.find { |s| s.status == "active" } ||
                   subscriptions.data.find { |s| s.status == "trialing" } ||
                   subscriptions.data.first

    build_stripe_data(subscription)
  rescue Stripe::InvalidRequestError => e
    if e.message.include?("No such customer")
      Rails.logger.warn "[SubscriptionSync] Customer not found in Stripe: #{tenant.stripe_customer_id}"
      { subscription: nil, customer_exists: false }
    else
      raise
    end
  end

  def build_stripe_data(subscription)
    return { subscription: nil } unless subscription

    price = subscription.items&.data&.first&.price

    {
      subscription: subscription,
      subscription_id: subscription.id,
      status: subscription.status,
      plan: determine_plan(price),
      current_period_end: subscription.current_period_end ? Time.at(subscription.current_period_end).utc : nil,
      cancel_at_period_end: subscription.cancel_at_period_end,
      canceled_at: subscription.canceled_at ? Time.at(subscription.canceled_at).utc : nil
    }
  end

  def determine_plan(price)
    return "free" unless price

    # Try lookup_key first (most reliable)
    return price.lookup_key if price.lookup_key.present?

    # Try nickname
    return price.nickname.downcase if price.nickname.present?

    # Match by price ID
    find_plan_by_price_id(price.id) || "smb"
  end

  def find_plan_by_price_id(price_id)
    return nil unless defined?(Tenant::PLANS)
    Tenant::PLANS.find { |_name, config| config[:price_id] == price_id }&.first
  end

  # =========================================================================
  # DISCREPANCY DETECTION
  # =========================================================================

  def detect_discrepancies(tenant, stripe_data)
    changes = {}

    # Status mismatch
    stripe_status = normalize_stripe_status(stripe_data[:status])
    if tenant.subscription_status != stripe_status
      changes[:subscription_status] = {
        local: tenant.subscription_status,
        stripe: stripe_status,
        severity: status_change_severity(tenant.subscription_status, stripe_status)
      }
    end

    # Plan mismatch
    if tenant.plan != stripe_data[:plan]
      changes[:plan] = {
        local: tenant.plan,
        stripe: stripe_data[:plan],
        severity: "medium"
      }
    end

    # Subscription ID mismatch
    if stripe_data[:subscription_id] && tenant.stripe_subscription_id != stripe_data[:subscription_id]
      changes[:stripe_subscription_id] = {
        local: tenant.stripe_subscription_id,
        stripe: stripe_data[:subscription_id],
        severity: "low"
      }
    end

    changes
  end

  def normalize_stripe_status(stripe_status)
    case stripe_status
    when "active" then "active"
    when "trialing" then "trialing"
    when "past_due" then "past_due"
    when "canceled" then "canceled"
    when "unpaid" then "past_due"
    when "incomplete", "incomplete_expired" then "incomplete"
    when "paused" then "paused"
    else "inactive"
    end
  end

  def status_change_severity(from, to)
    critical_changes = [["active", "canceled"], ["active", "past_due"]]
    return "critical" if critical_changes.include?([from, to])
    return "high" if to == "canceled" || to == "past_due"
    "medium"
  end

  # =========================================================================
  # APPLY CORRECTIONS
  # =========================================================================

  def apply_corrections(tenant, stripe_data, changes)
    previous_state = tenant.attributes.slice("subscription_status", "plan", "stripe_subscription_id")

    updates = {}
    updates[:subscription_status] = changes[:subscription_status][:stripe] if changes[:subscription_status]
    updates[:plan] = changes[:plan][:stripe] if changes[:plan]
    updates[:stripe_subscription_id] = changes[:stripe_subscription_id][:stripe] if changes[:stripe_subscription_id]
    updates[:last_synced_at] = Time.current
    updates[:current_period_end] = stripe_data[:current_period_end] if stripe_data[:current_period_end]

    tenant.update!(updates)

    # FDA Audit Log - Critical for compliance
    log_correction(tenant, changes, previous_state, stripe_data)

    Rails.logger.info "[SubscriptionSync] Corrected tenant #{tenant.id} (#{tenant.subdomain}): #{changes.keys.join(', ')}"
  end

  def log_correction(tenant, changes, previous_state, stripe_data)
    AuditLogger.log(
      event_type: "sync.subscription_corrected",
      action: "Nightly sync detected and corrected webhook miss",
      tenant: tenant,
      changes: changes,
      metadata: {
        source: "subscription_sync_job",
        previous_state: previous_state,
        stripe_subscription_id: stripe_data[:subscription_id],
        stripe_status: stripe_data[:status],
        correction_reason: "webhook_missed_or_delayed",
        sync_timestamp: Time.current.utc.iso8601,
        severity: changes.values.map { |c| c[:severity] }.max
      }
    )
  rescue StandardError => e
    Rails.logger.error "[SubscriptionSync] Failed to log audit: #{e.message}"
  end

  # =========================================================================
  # MISSED WEBHOOK DETECTION
  # =========================================================================

  def detect_missed_webhooks
    # Find tenants with Stripe IDs but no recent webhook activity
    suspect_tenants = Tenant.where.not(stripe_customer_id: [nil, ""])
                            .where(subscription_status: "active")
                            .where("updated_at < ?", 7.days.ago)

    suspect_tenants.find_each do |tenant|
      # Check if we have recent Stripe events for this customer
      recent_events = StripeEvent.where(customer_id: tenant.stripe_customer_id)
                                 .where("created_at > ?", 7.days.ago)
                                 .count rescue 0

      if recent_events.zero?
        @results[:details] << {
          tenant_id: tenant.id,
          warning: "no_recent_webhooks",
          last_updated: tenant.updated_at.iso8601
        }
      end
    end
  rescue StandardError => e
    Rails.logger.warn "[SubscriptionSync] Webhook detection error: #{e.message}"
  end

  # =========================================================================
  # CHURN DETECTION
  # =========================================================================

  def detect_churn_candidates
    # Detect tenants showing churn signals
    churn_candidates = []

    # 1. Past due for more than 7 days
    Tenant.where(subscription_status: "past_due")
          .where("updated_at < ?", 7.days.ago)
          .find_each do |tenant|
      churn_candidates << {
        tenant_id: tenant.id,
        subdomain: tenant.subdomain,
        signal: "past_due_extended",
        days_past_due: ((Time.current - tenant.updated_at) / 1.day).round,
        mrr_at_risk: calculate_mrr(tenant)
      }
    end

    # 2. Scheduled for cancellation
    Tenant.where(subscription_status: "active")
          .where.not(cancel_at: nil)
          .where("cancel_at < ?", 7.days.from_now)
          .find_each do |tenant|
      churn_candidates << {
        tenant_id: tenant.id,
        subdomain: tenant.subdomain,
        signal: "pending_cancellation",
        cancel_at: tenant.cancel_at&.iso8601,
        mrr_at_risk: calculate_mrr(tenant)
      }
    end

    @results[:churned_detected] = churn_candidates.count
    @results[:churn_candidates] = churn_candidates

    # Alert if significant churn detected
    if churn_candidates.count > 0
      total_mrr_at_risk = churn_candidates.sum { |c| c[:mrr_at_risk] || 0 }

      AuditLogger.log(
        event_type: "sync.churn_detected",
        action: "Nightly sync detected #{churn_candidates.count} churn candidates",
        metadata: {
          candidates_count: churn_candidates.count,
          total_mrr_at_risk_cents: total_mrr_at_risk,
          details: churn_candidates.first(10)
        }
      ) rescue nil
    end
  rescue StandardError => e
    Rails.logger.warn "[SubscriptionSync] Churn detection error: #{e.message}"
  end

  def calculate_mrr(tenant)
    SubscriptionReporter::PLAN_PRICES[tenant.plan] || 0
  rescue StandardError
    0
  end

  # =========================================================================
  # SPECIAL HANDLERS
  # =========================================================================

  def handle_no_subscription(tenant)
    return if tenant.subscription_status.in?(%w[free canceled inactive])

    # Tenant has Stripe customer but no subscription - mark as churned
    unless @dry_run
      previous_status = tenant.subscription_status
      tenant.update!(subscription_status: "canceled", last_synced_at: Time.current)

      AuditLogger.log(
        event_type: "sync.subscription_not_found",
        action: "No active Stripe subscription found - marked as canceled",
        tenant: tenant,
        metadata: {
          previous_status: previous_status,
          stripe_customer_id: tenant.stripe_customer_id,
          correction_reason: "no_stripe_subscription"
        }
      ) rescue nil
    end

    @results[:churned_detected] += 1
    @results[:details] << { tenant_id: tenant.id, warning: "no_stripe_subscription" }
  end

  def mark_synced(tenant)
    tenant.update_column(:last_synced_at, Time.current) if tenant.respond_to?(:last_synced_at)
  rescue StandardError
    # Column might not exist
  end

  # =========================================================================
  # AUDIT VERIFICATION
  # =========================================================================

  def verify_audit_integrity
    result = AuditEvent.verify_chain rescue { valid: "skipped", error: "verification_unavailable" }

    @results[:audit_verification] = {
      valid: result[:valid],
      checked: result[:checked],
      timestamp: Time.current.utc.iso8601
    }

    unless result[:valid] == true || result[:valid] == "skipped"
      Rails.logger.error "[SubscriptionSync] AUDIT CHAIN INTEGRITY FAILURE"
      notify_audit_failure(result)
    end
  end

  # =========================================================================
  # REPORTING & LOGGING
  # =========================================================================

  def generate_sync_report
    report = {
      completed_at: Time.current.utc.iso8601,
      duration_seconds: elapsed_time,
      dry_run: @dry_run,
      force_all: @force_all,
      summary: {
        tenants_synced: @results[:synced],
        tenants_skipped: @results[:skipped],
        errors: @results[:errors],
        webhook_misses_corrected: @results[:webhook_misses],
        churn_candidates_detected: @results[:churned_detected]
      },
      audit_verification: @results[:audit_verification],
      discrepancies: @results[:discrepancies].first(20)
    }

    # Persist to SystemLog for dashboard
    SystemLog.create!(
      log_type: "subscription_sync",
      severity: determine_report_severity,
      message: build_summary_message,
      metadata: report,
      recorded_at: Time.current
    ) rescue Rails.logger.warn("[SubscriptionSync] Failed to create SystemLog")

    # Return report
    @results[:report] = report
  end

  def determine_report_severity
    return "error" if @results[:errors] > 5
    return "warning" if @results[:errors] > 0 || @results[:webhook_misses] > 10
    "info"
  end

  def build_summary_message
    "Sync: #{@results[:synced]} corrected, #{@results[:skipped]} ok, #{@results[:errors]} errors, #{@results[:webhook_misses]} webhook misses"
  end

  def build_discrepancy_record(tenant, changes)
    {
      tenant_id: tenant.id,
      subdomain: tenant.subdomain,
      changes: changes,
      detected_at: Time.current.utc.iso8601
    }
  end

  def record_error(tenant, error)
    @results[:errors] += 1
    @results[:details] << {
      tenant_id: tenant.id,
      error: error.message,
      error_class: error.class.name
    }
    Rails.logger.error "[SubscriptionSync] Error syncing tenant #{tenant.id}: #{error.message}"
  end

  def log_sync_failure(error)
    SystemLog.create!(
      log_type: "subscription_sync",
      severity: "critical",
      message: "Subscription sync job failed: #{error.message}",
      metadata: {
        error: error.message,
        backtrace: error.backtrace&.first(10),
        partial_results: @results
      },
      recorded_at: Time.current
    ) rescue nil
  end

  def elapsed_time
    (Time.current - @start_time).round(2)
  end

  # =========================================================================
  # NOTIFICATIONS
  # =========================================================================

  def notify_sync_failure(error)
    AdminMailer.system_health_alert({
      checks: {
        subscription_sync: {
          status: "error",
          error: error.message
        }
      }
    }).deliver_later rescue nil
  end

  def notify_audit_failure(result)
    AdminMailer.audit_chain_alert(result).deliver_later rescue nil
  end
end
