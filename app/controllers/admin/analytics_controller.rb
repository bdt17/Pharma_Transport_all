# frozen_string_literal: true

# =============================================================================
# Admin::AnalyticsController
# =============================================================================
# EXECUTIVE DASHBOARD: Real-time subscription analytics with MRR, churn, LTV
# FDA 21 CFR Part 11 Compliant - Access logged to audit trail
#
# Routes:
#   GET /admin/analytics        → Full dashboard
#   GET /admin/analytics/mrr    → MRR details (JSON)
#   GET /admin/analytics/churn  → Churn analysis (JSON)
#   GET /admin/analytics/export → CSV export
#
# Console Testing:
#   # Verify controller loads
#   Admin::AnalyticsController.new
# =============================================================================

module Admin
  class AnalyticsController < ApplicationController
    before_action :authenticate_admin!
    before_action :log_admin_access

    # =========================================================================
    # GET /admin/analytics
    # Main dashboard view with all metrics
    # =========================================================================
    def index
      @dashboard = SubscriptionReporter.executive_dashboard
      @mrr = @dashboard[:mrr]
      @churn = @dashboard[:churn]
      @tenants = @dashboard[:tenants]
      @ltv = @dashboard[:ltv]
      @at_risk = @dashboard[:at_risk]
      @alerts = @dashboard[:alerts]
      @trends = @dashboard[:trends]

      respond_to do |format|
        format.html
        format.json { render json: @dashboard }
      end
    end

    # =========================================================================
    # GET /admin/analytics/mrr
    # Detailed MRR breakdown
    # =========================================================================
    def mrr
      @mrr = SubscriptionReporter.monthly_mrr
      @breakdown = @mrr[:breakdown]
      @trend = SubscriptionReporter.revenue_trend(6)

      respond_to do |format|
        format.html { render :mrr }
        format.json { render json: { mrr: @mrr, trend: @trend } }
      end
    end

    # =========================================================================
    # GET /admin/analytics/churn
    # Churn analysis with at-risk tenants
    # =========================================================================
    def churn
      @churn_30 = SubscriptionReporter.churn_rate(30)
      @churn_90 = SubscriptionReporter.churn_rate(90)
      @at_risk = SubscriptionReporter.at_risk_tenants
      @cohorts = SubscriptionReporter.cohort_analysis(6)

      respond_to do |format|
        format.html { render :churn }
        format.json do
          render json: {
            churn_30_day: @churn_30,
            churn_90_day: @churn_90,
            at_risk: @at_risk,
            cohorts: @cohorts
          }
        end
      end
    end

    # =========================================================================
    # GET /admin/analytics/tenants
    # Tenant breakdown by status and plan
    # =========================================================================
    def tenants
      @tenants = SubscriptionReporter.active_tenants
      @tenant_list = Tenant.includes(:users)
                           .order(created_at: :desc)
                           .limit(100)

      respond_to do |format|
        format.html { render :tenants }
        format.json { render json: @tenants }
      end
    end

    # =========================================================================
    # GET /admin/analytics/export
    # Export analytics as CSV
    # =========================================================================
    def export
      dashboard = SubscriptionReporter.executive_dashboard

      csv_data = generate_csv(dashboard)

      send_data csv_data,
                filename: "pharma_analytics_#{Date.current.iso8601}.csv",
                type: "text/csv"

      # Log export for compliance
      AuditLogger.log(
        event_type: "admin.analytics_export",
        action: "Admin exported analytics dashboard",
        user: current_user,
        metadata: { export_date: Date.current.iso8601 }
      ) rescue nil
    end

    # =========================================================================
    # POST /admin/analytics/sync
    # Trigger manual subscription sync
    # =========================================================================
    def sync
      unless Rails.env.production?
        result = SubscriptionSyncJob.new.perform("dry_run" => params[:dry_run] == "true")
        render json: { status: "completed", result: result }
      else
        SubscriptionSyncJob.perform_async("dry_run" => params[:dry_run] == "true")
        render json: { status: "queued", message: "Sync job queued for background processing" }
      end
    end

    private

    # =========================================================================
    # AUTHENTICATION
    # =========================================================================

    def authenticate_admin!
      # Check for admin user
      unless current_user&.admin?
        respond_to do |format|
          format.html { redirect_to root_path, alert: "Admin access required" }
          format.json { render json: { error: "Unauthorized" }, status: :unauthorized }
        end
      end
    end

    def current_user
      # Implement based on your auth system
      @current_user ||= begin
        if session[:user_id]
          User.find_by(id: session[:user_id])
        elsif request.headers["Authorization"]
          token = request.headers["Authorization"].to_s.split(" ").last
          User.find_by(api_token: token)
        end
      end
    end

    # =========================================================================
    # AUDIT LOGGING
    # =========================================================================

    def log_admin_access
      AuditLogger.log(
        event_type: "admin.analytics_access",
        action: "Admin accessed analytics dashboard",
        user: current_user,
        metadata: {
          action: action_name,
          ip: request.remote_ip,
          user_agent: request.user_agent
        }
      ) rescue nil
    end

    # =========================================================================
    # CSV EXPORT
    # =========================================================================

    def generate_csv(dashboard)
      require "csv"

      CSV.generate(headers: true) do |csv|
        csv << ["Pharma Transport Analytics Report"]
        csv << ["Generated", Time.current.utc.iso8601]
        csv << []

        # Summary
        csv << ["EXECUTIVE SUMMARY"]
        csv << ["Metric", "Value"]
        csv << ["MRR", dashboard.dig(:summary, :mrr)]
        csv << ["ARR", dashboard.dig(:summary, :arr)]
        csv << ["Active Tenants", dashboard.dig(:summary, :active_tenants)]
        csv << ["Paying Tenants", dashboard.dig(:summary, :paying_tenants)]
        csv << ["Churn Rate (30d)", dashboard.dig(:summary, :churn_rate)]
        csv << ["Retention Rate", dashboard.dig(:summary, :retention)]
        csv << ["LTV", dashboard.dig(:summary, :ltv)]
        csv << []

        # MRR Breakdown
        csv << ["MRR BY PLAN"]
        csv << ["Plan", "Count", "MRR", "Percentage"]
        dashboard.dig(:mrr, :breakdown)&.each do |plan, data|
          csv << [plan, data[:count], data[:mrr_formatted], "#{data[:percentage]}%"]
        end
        csv << []

        # Tenant Status
        csv << ["TENANT STATUS"]
        csv << ["Status", "Count"]
        dashboard.dig(:tenants, :by_status)&.each do |status, count|
          csv << [status, count]
        end
        csv << []

        # At Risk
        csv << ["AT-RISK TENANTS"]
        csv << ["ID", "Company", "Plan", "Risk Level", "Reason", "MRR at Risk"]
        dashboard.dig(:at_risk, :tenants)&.first(20)&.each do |tenant|
          csv << [
            tenant[:tenant_id],
            tenant[:company_name],
            tenant[:plan],
            tenant[:risk_level],
            tenant[:reason],
            tenant[:mrr_at_risk_cents].to_i / 100.0
          ]
        end
      end
    end
  end
end
