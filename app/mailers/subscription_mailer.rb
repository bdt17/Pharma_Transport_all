# frozen_string_literal: true

# =============================================================================
# SubscriptionMailer
# =============================================================================
# Customer-facing subscription notifications
# FDA 21 CFR Part 11 Compliant - All emails logged to audit trail
#
# Usage:
#   SubscriptionMailer.welcome(tenant).deliver_later
#   SubscriptionMailer.payment_succeeded(tenant, invoice).deliver_later
#   SubscriptionMailer.payment_failed(tenant, invoice, attempt).deliver_later
# =============================================================================

class SubscriptionMailer < ApplicationMailer
  default from: "billing@pharmatransport.io"
  layout "mailer"

  # =========================================================================
  # WELCOME & ACTIVATION
  # =========================================================================

  def welcome(tenant)
    @tenant = tenant
    @plan = Tenant::PLANS[@tenant.plan]
    @dashboard_url = dashboard_url

    log_email_sent("welcome", tenant)

    mail(
      to: tenant.billing_email,
      subject: "Welcome to PharmaTransport - Your #{@tenant.plan.titleize} Plan is Active"
    )
  end

  def subscription_activated(tenant, plan_name = nil)
    @tenant = tenant
    @plan_name = plan_name || tenant.plan
    @plan = Tenant::PLANS[@plan_name]
    @activation_date = Time.current

    log_email_sent("subscription_activated", tenant)

    mail(
      to: tenant.billing_email,
      subject: "Your PharmaTransport #{@plan_name.titleize} Subscription is Now Active"
    )
  end

  # =========================================================================
  # PAYMENT NOTIFICATIONS
  # =========================================================================

  def payment_succeeded(tenant, invoice_data = {})
    @tenant = tenant
    @amount = format_currency(invoice_data[:amount_paid] || 0)
    @invoice_id = invoice_data[:invoice_id]
    @next_billing_date = invoice_data[:next_billing_date] || 1.month.from_now
    @receipt_url = invoice_data[:receipt_url]

    log_email_sent("payment_succeeded", tenant, { amount: @amount })

    mail(
      to: tenant.billing_email,
      subject: "Payment Received - #{@amount} - PharmaTransport"
    )
  end

  def payment_failed(tenant, invoice_data = {}, attempt_count = 1)
    @tenant = tenant
    @amount = format_currency(invoice_data[:amount_due] || 0)
    @attempt_count = attempt_count
    @next_retry_date = invoice_data[:next_retry_date]
    @update_payment_url = billing_url
    @failure_reason = invoice_data[:failure_reason] || "Card declined"

    # Determine urgency based on attempt
    @urgency = case attempt_count
               when 1 then "low"
               when 2 then "medium"
               when 3 then "high"
               else "critical"
               end

    log_email_sent("payment_failed", tenant, { attempt: attempt_count, amount: @amount })

    mail(
      to: tenant.billing_email,
      subject: payment_failed_subject(attempt_count)
    )
  end

  def final_payment_warning(tenant)
    @tenant = tenant
    @suspension_date = 3.days.from_now
    @update_payment_url = billing_url

    log_email_sent("final_payment_warning", tenant)

    mail(
      to: tenant.billing_email,
      subject: "[URGENT] Final Notice - Update Payment to Avoid Service Interruption"
    )
  end

  # =========================================================================
  # SUBSCRIPTION CHANGES
  # =========================================================================

  def plan_upgraded(tenant, old_plan, new_plan)
    @tenant = tenant
    @old_plan = Tenant::PLANS[old_plan]
    @new_plan = Tenant::PLANS[new_plan]
    @old_plan_name = old_plan
    @new_plan_name = new_plan
    @effective_date = Time.current

    log_email_sent("plan_upgraded", tenant, { from: old_plan, to: new_plan })

    mail(
      to: tenant.billing_email,
      subject: "Plan Upgraded to #{new_plan.titleize} - PharmaTransport"
    )
  end

  def plan_downgraded(tenant, old_plan, new_plan, effective_date = nil)
    @tenant = tenant
    @old_plan = Tenant::PLANS[old_plan]
    @new_plan = Tenant::PLANS[new_plan]
    @old_plan_name = old_plan
    @new_plan_name = new_plan
    @effective_date = effective_date || Time.current

    log_email_sent("plan_downgraded", tenant, { from: old_plan, to: new_plan })

    mail(
      to: tenant.billing_email,
      subject: "Plan Change Scheduled - PharmaTransport"
    )
  end

  def subscription_cancelled(tenant, cancellation_date = nil)
    @tenant = tenant
    @cancellation_date = cancellation_date || Time.current
    @reactivate_url = billing_url

    log_email_sent("subscription_cancelled", tenant)

    mail(
      to: tenant.billing_email,
      subject: "Subscription Cancelled - We're Sorry to See You Go"
    )
  end

  def subscription_reactivated(tenant)
    @tenant = tenant
    @plan = Tenant::PLANS[@tenant.plan]
    @reactivation_date = Time.current

    log_email_sent("subscription_reactivated", tenant)

    mail(
      to: tenant.billing_email,
      subject: "Welcome Back! Your PharmaTransport Subscription is Reactivated"
    )
  end

  # =========================================================================
  # RENEWAL NOTIFICATIONS
  # =========================================================================

  def renewal_reminder(tenant, days_until_renewal = 7)
    @tenant = tenant
    @renewal_date = days_until_renewal.days.from_now
    @amount = format_currency(tenant.monthly_price_cents)
    @days_until = days_until_renewal
    @manage_url = billing_url

    log_email_sent("renewal_reminder", tenant, { days: days_until_renewal })

    mail(
      to: tenant.billing_email,
      subject: "Subscription Renewal in #{days_until_renewal} Days - PharmaTransport"
    )
  end

  def annual_renewal_reminder(tenant)
    @tenant = tenant
    @renewal_date = 30.days.from_now
    @annual_amount = format_currency((tenant.monthly_price_cents || 0) * 12)
    @manage_url = billing_url

    log_email_sent("annual_renewal_reminder", tenant)

    mail(
      to: tenant.billing_email,
      subject: "Annual Subscription Renewal Coming Up - PharmaTransport"
    )
  end

  # =========================================================================
  # TRIAL NOTIFICATIONS
  # =========================================================================

  def trial_started(tenant, trial_days = 14)
    @tenant = tenant
    @trial_end_date = trial_days.days.from_now
    @trial_days = trial_days
    @upgrade_url = billing_url

    log_email_sent("trial_started", tenant, { trial_days: trial_days })

    mail(
      to: tenant.billing_email,
      subject: "Your #{trial_days}-Day Free Trial Has Started - PharmaTransport"
    )
  end

  def trial_ending_soon(tenant, days_remaining = 3)
    @tenant = tenant
    @days_remaining = days_remaining
    @trial_end_date = days_remaining.days.from_now
    @upgrade_url = billing_url

    log_email_sent("trial_ending_soon", tenant, { days_remaining: days_remaining })

    mail(
      to: tenant.billing_email,
      subject: "#{days_remaining} Days Left in Your Trial - Upgrade Now"
    )
  end

  def trial_expired(tenant)
    @tenant = tenant
    @upgrade_url = billing_url

    log_email_sent("trial_expired", tenant)

    mail(
      to: tenant.billing_email,
      subject: "Your Trial Has Ended - Upgrade to Continue"
    )
  end

  private

  # =========================================================================
  # HELPERS
  # =========================================================================

  def format_currency(cents)
    "$#{'%.2f' % (cents.to_f / 100)}"
  end

  def payment_failed_subject(attempt)
    case attempt
    when 1
      "Payment Failed - Please Update Your Payment Method"
    when 2
      "[Action Required] Second Payment Attempt Failed"
    when 3
      "[URGENT] Final Payment Attempt - Update Payment Method Now"
    else
      "[CRITICAL] Service Suspension Imminent - Update Payment"
    end
  end

  def log_email_sent(email_type, tenant, metadata = {})
    AuditLogger.log(
      event_type: "email.#{email_type}",
      action: "Subscription email sent: #{email_type}",
      tenant: tenant,
      metadata: metadata.merge(
        recipient: tenant.billing_email,
        timestamp: Time.current.utc.iso8601
      )
    ) rescue nil
  end
end
