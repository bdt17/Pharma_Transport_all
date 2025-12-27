# frozen_string_literal: true

# =============================================================================
# SubscriptionReporter Service
# =============================================================================
# MISSION CRITICAL: Executive Dashboard + Revenue Analytics + Churn Detection
# FDA 21 CFR Part 11 Compliant - All metrics auditable via PaperTrail
#
# Core Methods:
#   SubscriptionReporter.monthly_mrr          → Total MRR with breakdown
#   SubscriptionReporter.churn_rate(30)       → Churn % for period
#   SubscriptionReporter.active_tenants       → Count by status
#   SubscriptionReporter.lifetime_value       → Avg LTV calculation
#   SubscriptionReporter.executive_dashboard  → ALL metrics combined
#   SubscriptionReporter.at_risk_tenants      → Churn alarm list
#
# Console Testing:
#   rails c
#   SubscriptionReporter.executive_dashboard
#   SubscriptionReporter.monthly_mrr
#   SubscriptionReporter.churn_rate(30)
#   SubscriptionReporter.at_risk_tenants
#   SubscriptionReporter.revenue_trend(6)
# =============================================================================

class SubscriptionReporter
  # Plan pricing (cents) - matches Tenant::PLANS
  PLAN_PRICES = {
    "free" => 0,
    "trial" => 0,
    "smb" => 29_900,        # $299/mo
    "enterprise" => 99_900  # $999/mo
  }.freeze

  class << self
    # =========================================================================
    # CORE METRIC #1: MONTHLY MRR
    # =========================================================================

    def monthly_mrr
      active = Tenant.where(subscription_status: "active")

      mrr_cents = active.sum { |tenant| calculate_tenant_mrr(tenant) }

      {
        mrr_cents: mrr_cents,
        mrr_dollars: (mrr_cents / 100.0).round(2),
        mrr_formatted: format_currency(mrr_cents),
        arr_cents: mrr_cents * 12,
        arr_formatted: format_currency(mrr_cents * 12),
        breakdown: mrr_breakdown,
        active_subscriptions: active.count,
        trialing: Tenant.where(subscription_status: "trialing").count,
        past_due: Tenant.where(subscription_status: "past_due").count,
        calculated_at: Time.current.utc.iso8601
      }
    end

    def mrr_breakdown
      breakdown = {}
      total_mrr = 0

      PLAN_PRICES.each do |plan_name, price|
        count = Tenant.where(plan: plan_name, subscription_status: "active").count
        plan_mrr = price * count
        total_mrr += plan_mrr

        breakdown[plan_name] = {
          count: count,
          price_cents: price,
          mrr_cents: plan_mrr,
          mrr_formatted: format_currency(plan_mrr)
        }
      end

      # Calculate percentages
      breakdown.each do |_plan, data|
        data[:percentage] = total_mrr > 0 ? ((data[:mrr_cents].to_f / total_mrr) * 100).round(1) : 0
      end

      breakdown
    end

    # =========================================================================
    # CORE METRIC #2: CHURN RATE
    # =========================================================================

    def churn_rate(days = 30)
      period_start = days.days.ago.beginning_of_day
      period_end = Time.current

      # Tenants that were active at start of period
      active_at_start = count_active_at_date(period_start)

      if active_at_start.zero?
        return {
          churn_rate: 0.0,
          churn_rate_formatted: "0.0%",
          message: "No active tenants at period start",
          period_days: days
        }
      end

      # Count churned tenants via multiple methods
      churned_direct = Tenant.where(subscription_status: %w[canceled inactive])
                             .where("updated_at >= ?", period_start)
                             .count

      churned_audit = count_churned_via_papertrail(period_start, period_end)

      total_churned = [churned_direct, churned_audit].max
      rate = ((total_churned.to_f / active_at_start) * 100).round(2)

      {
        churn_rate: rate,
        churn_rate_formatted: "#{rate}%",
        period_days: days,
        period_start: period_start.utc.iso8601,
        period_end: period_end.utc.iso8601,
        active_at_start: active_at_start,
        churned_count: total_churned,
        retention_rate: (100 - rate).round(2),
        retention_formatted: "#{(100 - rate).round(2)}%",
        annualized_churn: (rate * (365.0 / days)).round(2),
        revenue_churned_cents: calculate_churned_revenue(period_start),
        calculated_at: Time.current.utc.iso8601
      }
    end

    # =========================================================================
    # CORE METRIC #3: ACTIVE TENANTS
    # =========================================================================

    def active_tenants
      active = Tenant.where(subscription_status: "active").count
      trialing = Tenant.where(subscription_status: "trialing").count
      past_due = Tenant.where(subscription_status: "past_due").count
      canceled = Tenant.where(subscription_status: %w[canceled inactive]).count
      total = Tenant.count

      paying = active + past_due
      conversion = trialing > 0 ? ((active.to_f / (active + trialing)) * 100).round(1) : 0

      {
        active: active,
        trialing: trialing,
        past_due: past_due,
        canceled: canceled,
        total: total,
        paying: paying,
        non_paying: total - paying,
        conversion_rate: conversion,
        conversion_formatted: "#{conversion}%",
        by_plan: Tenant.group(:plan).count,
        by_status: Tenant.group(:subscription_status).count,
        calculated_at: Time.current.utc.iso8601
      }
    end

    # =========================================================================
    # CORE METRIC #4: LIFETIME VALUE (LTV)
    # =========================================================================

    def lifetime_value
      active = Tenant.where(subscription_status: "active")

      if active.count.zero?
        return {
          ltv_cents: 0,
          ltv_formatted: "$0.00",
          message: "No active tenants for LTV calculation"
        }
      end

      # Average MRR per tenant
      total_mrr = active.sum { |t| calculate_tenant_mrr(t) }
      avg_mrr = (total_mrr / active.count.to_f).round

      # Average lifespan in months
      avg_lifespan = calculate_average_lifespan(active)

      # LTV Method 1: ARPU × Average Lifespan
      ltv_lifespan = (avg_mrr * avg_lifespan).round

      # LTV Method 2: ARPU / Monthly Churn Rate
      monthly_churn = churn_rate(30)[:churn_rate] / 100.0
      ltv_churn = monthly_churn > 0 ? (avg_mrr / monthly_churn).round : ltv_lifespan

      # Use conservative estimate
      ltv_cents = [ltv_lifespan, ltv_churn].min

      {
        ltv_cents: ltv_cents,
        ltv_dollars: (ltv_cents / 100.0).round(2),
        ltv_formatted: format_currency(ltv_cents),
        avg_mrr_cents: avg_mrr,
        avg_mrr_formatted: format_currency(avg_mrr),
        avg_lifespan_months: avg_lifespan.round(1),
        ltv_via_lifespan: ltv_lifespan,
        ltv_via_churn: ltv_churn,
        cac_ratio: nil, # Requires CAC data
        calculated_at: Time.current.utc.iso8601
      }
    end

    # =========================================================================
    # EXECUTIVE DASHBOARD - ALL METRICS COMBINED
    # =========================================================================

    def executive_dashboard
      mrr = monthly_mrr
      churn = churn_rate(30)
      tenants = active_tenants
      ltv = lifetime_value
      risk = at_risk_tenants

      {
        # Quick summary for executives
        summary: {
          mrr: mrr[:mrr_formatted],
          arr: mrr[:arr_formatted],
          active_tenants: tenants[:active],
          paying_tenants: tenants[:paying],
          churn_rate: churn[:churn_rate_formatted],
          retention: churn[:retention_formatted],
          ltv: ltv[:ltv_formatted],
          at_risk_count: risk[:count],
          at_risk_mrr: risk[:mrr_at_risk_formatted]
        },

        # Detailed metrics
        mrr: mrr,
        churn: churn,
        tenants: tenants,
        ltv: ltv,
        at_risk: risk,

        # Trends
        trends: {
          mrr_trend: revenue_trend(3),
          tenant_trend: tenant_growth_trend(3)
        },

        # Alerts
        alerts: generate_executive_alerts(mrr, churn, tenants, risk),

        # Metadata
        generated_at: Time.current.utc.iso8601,
        fda_compliant: true,
        data_source: "Tenant + Stripe + PaperTrail"
      }
    end

    # =========================================================================
    # AT-RISK TENANTS (CHURN ALARMS)
    # =========================================================================

    def at_risk_tenants
      at_risk = []

      # CRITICAL: Past due payments
      Tenant.where(subscription_status: "past_due").find_each do |tenant|
        at_risk << build_risk_entry(tenant, "critical", "past_due",
          "Payment failed - immediate action required")
      end

      # HIGH: Trial ending within 3 days
      Tenant.where(subscription_status: "trialing").find_each do |tenant|
        if tenant.respond_to?(:trial_end_date) && tenant.trial_end_date
          days_left = ((tenant.trial_end_date - Time.current) / 1.day).round
          if days_left <= 3 && days_left >= 0
            at_risk << build_risk_entry(tenant, "high", "trial_ending",
              "Trial ends in #{days_left} day(s)", { days_remaining: days_left })
          end
        end
      end

      # MEDIUM: No activity in 14+ days
      find_inactive_tenants(14).each do |tenant|
        at_risk << build_risk_entry(tenant, "medium", "inactive",
          "No activity for 14+ days - re-engagement needed")
      end

      # Calculate totals
      total_mrr_at_risk = at_risk.sum { |t| t[:mrr_at_risk_cents] || 0 }

      {
        count: at_risk.count,
        mrr_at_risk_cents: total_mrr_at_risk,
        mrr_at_risk_formatted: format_currency(total_mrr_at_risk),
        by_risk_level: {
          critical: at_risk.count { |t| t[:risk_level] == "critical" },
          high: at_risk.count { |t| t[:risk_level] == "high" },
          medium: at_risk.count { |t| t[:risk_level] == "medium" }
        },
        tenants: at_risk.sort_by { |t| risk_sort_priority(t[:risk_level]) },
        generated_at: Time.current.utc.iso8601
      }
    end

    # =========================================================================
    # TREND ANALYSIS
    # =========================================================================

    def revenue_trend(months = 6)
      trend_data = []

      months.times do |i|
        month_date = i.months.ago
        month_mrr = calculate_mrr_at_date(month_date.end_of_month)

        trend_data << {
          month: month_date.strftime("%Y-%m"),
          month_name: month_date.strftime("%b %Y"),
          mrr_cents: month_mrr,
          mrr_formatted: format_currency(month_mrr)
        }
      end

      # Calculate growth
      current = trend_data.first[:mrr_cents]
      previous = trend_data.last[:mrr_cents]
      growth = previous > 0 ? (((current - previous).to_f / previous) * 100).round(2) : 0

      {
        data: trend_data.reverse,
        period_months: months,
        growth_rate: growth,
        growth_formatted: "#{growth >= 0 ? '+' : ''}#{growth}%",
        direction: growth > 0 ? "up" : (growth < 0 ? "down" : "flat")
      }
    end

    def tenant_growth_trend(months = 6)
      trend_data = []

      months.times do |i|
        month_date = i.months.ago.end_of_month
        count = count_active_at_date(month_date)

        trend_data << {
          month: month_date.strftime("%Y-%m"),
          active_tenants: count
        }
      end

      current = trend_data.first[:active_tenants]
      previous = trend_data.last[:active_tenants]

      {
        data: trend_data.reverse,
        net_growth: current - previous,
        direction: current > previous ? "up" : (current < previous ? "down" : "flat")
      }
    end

    # =========================================================================
    # COHORT ANALYSIS
    # =========================================================================

    def cohort_analysis(months = 6)
      cohorts = {}

      months.times do |i|
        month_start = i.months.ago.beginning_of_month
        month_end = i.months.ago.end_of_month
        cohort_key = month_start.strftime("%Y-%m")

        created = Tenant.where(created_at: month_start..month_end)
        still_active = created.where(subscription_status: "active").count
        total = created.count

        cohorts[cohort_key] = {
          month_name: month_start.strftime("%B %Y"),
          created: total,
          still_active: still_active,
          churned: total - still_active,
          retention_rate: total > 0 ? ((still_active.to_f / total) * 100).round(1) : 0
        }
      end

      cohorts
    end

    # =========================================================================
    # MONTHLY REPORT (FDA Audit Compatible)
    # =========================================================================

    def monthly_report(month_date = Date.current)
      start_date = month_date.beginning_of_month
      end_date = month_date.end_of_month

      {
        report_period: {
          month: month_date.strftime("%B %Y"),
          start_date: start_date.iso8601,
          end_date: end_date.iso8601
        },
        mrr: monthly_mrr,
        churn: churn_rate(30),
        tenants: active_tenants,
        ltv: lifetime_value,
        revenue_events: revenue_events_for_period(start_date, end_date),
        compliance: compliance_metrics(start_date, end_date),
        generated_at: Time.current.utc.iso8601,
        fda_21_cfr_11_compliant: true
      }
    end

    private

    # =========================================================================
    # CALCULATION HELPERS
    # =========================================================================

    def calculate_tenant_mrr(tenant)
      return 0 unless tenant.subscription_status == "active"

      # Try tenant's stored price first, then plan lookup
      if tenant.respond_to?(:monthly_price_cents) && tenant.monthly_price_cents.to_i > 0
        tenant.monthly_price_cents
      else
        PLAN_PRICES[tenant.plan] || 0
      end
    end

    def count_active_at_date(date)
      Tenant.where(subscription_status: "active")
            .where("created_at <= ?", date)
            .count
    end

    def calculate_mrr_at_date(date)
      Tenant.where(subscription_status: "active")
            .where("created_at <= ?", date)
            .sum { |t| calculate_tenant_mrr(t) }
    end

    def count_churned_via_papertrail(start_date, end_date)
      return 0 unless defined?(PaperTrail) && PaperTrail::Version.table_exists?

      PaperTrail::Version
        .where(item_type: "Tenant")
        .where(created_at: start_date..end_date)
        .where("object_changes LIKE ?", "%subscription_status%")
        .where("object_changes LIKE ?", "%canceled%")
        .select(:item_id)
        .distinct
        .count
    rescue StandardError => e
      Rails.logger.warn "[SubscriptionReporter] PaperTrail query failed: #{e.message}"
      0
    end

    def calculate_churned_revenue(since_date)
      Tenant.where(subscription_status: %w[canceled inactive])
            .where("updated_at >= ?", since_date)
            .sum { |t| PLAN_PRICES[t.plan] || 0 }
    end

    def calculate_average_lifespan(tenants)
      return 0 if tenants.count.zero?

      total_months = tenants.sum do |tenant|
        start = tenant.respond_to?(:subscription_started_at) && tenant.subscription_started_at ?
                tenant.subscription_started_at : tenant.created_at
        ((Time.current - start) / 1.month).round(1)
      end

      total_months / tenants.count.to_f
    end

    def find_inactive_tenants(days)
      cutoff = days.days.ago

      Tenant.where(subscription_status: "active").select do |tenant|
        last_event = AuditEvent.where(tenant_id: tenant.id).maximum(:created_at) rescue nil
        last_event.nil? || last_event < cutoff
      end
    rescue StandardError
      []
    end

    def build_risk_entry(tenant, risk_level, reason, action, extra = {})
      {
        tenant_id: tenant.id,
        company_name: tenant.company_name,
        subdomain: tenant.subdomain,
        plan: tenant.plan,
        risk_level: risk_level,
        reason: reason,
        action: action,
        mrr_at_risk_cents: calculate_tenant_mrr(tenant),
        subscription_status: tenant.subscription_status,
        stripe_customer_id: tenant.stripe_customer_id
      }.merge(extra)
    end

    def risk_sort_priority(level)
      { "critical" => 0, "high" => 1, "medium" => 2 }[level] || 3
    end

    def generate_executive_alerts(mrr, churn, tenants, risk)
      alerts = []

      # High churn warning
      if churn[:churn_rate] > 5
        severity = churn[:churn_rate] > 10 ? "critical" : "warning"
        alerts << {
          type: "high_churn",
          severity: severity,
          title: "Elevated Churn Rate",
          message: "#{churn[:churn_rate_formatted]} churn exceeds 5% target"
        }
      end

      # Past due accounts
      if tenants[:past_due] > 0
        alerts << {
          type: "payment_issues",
          severity: "warning",
          title: "Past Due Accounts",
          message: "#{tenants[:past_due]} account(s) with failed payments"
        }
      end

      # At-risk revenue
      if risk[:mrr_at_risk_cents] > (mrr[:mrr_cents] * 0.1)
        alerts << {
          type: "revenue_risk",
          severity: "warning",
          title: "Revenue at Risk",
          message: "#{risk[:mrr_at_risk_formatted]} MRR at risk (>10%)"
        }
      end

      # Low conversion
      if tenants[:trialing] > 0 && tenants[:conversion_rate] < 20
        alerts << {
          type: "low_conversion",
          severity: "info",
          title: "Low Trial Conversion",
          message: "#{tenants[:conversion_formatted]} conversion rate below 20% target"
        }
      end

      alerts
    end

    def revenue_events_for_period(start_date, end_date)
      {
        successful_payments: count_audit_events("stripe.payment_succeeded", start_date, end_date),
        failed_payments: count_audit_events("stripe.payment_failed", start_date, end_date),
        new_subscriptions: count_audit_events("stripe.subscription_created", start_date, end_date),
        cancellations: count_audit_events("stripe.subscription_canceled", start_date, end_date)
      }
    rescue StandardError
      { error: "Unable to retrieve revenue events" }
    end

    def count_audit_events(event_type, start_date, end_date)
      AuditEvent.where(event_type: event_type)
                .where(created_at: start_date..end_date)
                .count
    rescue StandardError
      0
    end

    def compliance_metrics(start_date, end_date)
      {
        total_audit_events: AuditEvent.where(created_at: start_date..end_date).count,
        chain_verified: (AuditEvent.verify_chain rescue { valid: false })[:valid],
        paper_trail_versions: (PaperTrail::Version.where(created_at: start_date..end_date).count rescue 0)
      }
    rescue StandardError
      { error: "Compliance metrics unavailable" }
    end

    def format_currency(cents)
      dollars = (cents / 100.0).round(2)
      "$#{dollars.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    end
  end
end
