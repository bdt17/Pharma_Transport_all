# frozen_string_literal: true

# =============================================================================
# Admin::ComplianceController
# =============================================================================
# FDA 21 CFR Part 11 Compliant Audit Trail Viewer
# Real-time access to AuditEvent + PaperTrail entries
#
# Routes:
#   GET /admin/compliance           - Main audit trail view
#   GET /admin/compliance/export    - Export audit logs as CSV
#   GET /admin/compliance/verify    - Verify chain integrity
#   GET /admin/compliance/report    - Generate compliance report
# =============================================================================

module Admin
  class ComplianceController < ApplicationController
    before_action :authenticate_admin!
    before_action :set_date_range

    # =========================================================================
    # GET /admin/compliance
    # Real-time audit trail viewer
    # =========================================================================
    def index
      @audit_events = filtered_audit_events
                        .order(created_at: :desc)
                        .page(params[:page])
                        .per(50)

      @paper_trail_versions = filtered_paper_trail_versions
                                .order(created_at: :desc)
                                .limit(100) if params[:include_versions]

      @stats = calculate_stats
      @chain_status = quick_chain_verification

      respond_to do |format|
        format.html
        format.json { render json: audit_json_response }
      end
    end

    # =========================================================================
    # GET /admin/compliance/export
    # Export audit logs as CSV
    # =========================================================================
    def export
      @audit_events = filtered_audit_events.order(:sequence)

      respond_to do |format|
        format.csv do
          send_data generate_csv(@audit_events),
                    filename: "fda_audit_export_#{Date.current}.csv",
                    type: "text/csv"
        end
        format.json do
          send_data @audit_events.map(&:to_audit_hash).to_json,
                    filename: "fda_audit_export_#{Date.current}.json",
                    type: "application/json"
        end
      end

      log_admin_action("audit_export", { format: request.format.to_s, count: @audit_events.count })
    end

    # =========================================================================
    # GET /admin/compliance/verify
    # Verify chain integrity
    # =========================================================================
    def verify
      @verification_result = AuditEvent.verify_chain(
        tenant_id: params[:tenant_id],
        start_seq: params[:start_seq],
        end_seq: params[:end_seq]
      )

      log_admin_action("audit_verification", @verification_result.slice(:valid, :checked))

      respond_to do |format|
        format.html { render :verify }
        format.json { render json: @verification_result }
      end
    end

    # =========================================================================
    # GET /admin/compliance/report
    # Generate FDA compliance report
    # =========================================================================
    def report
      tenant_id = params[:tenant_id]

      unless tenant_id
        return render json: { error: "tenant_id required" }, status: :unprocessable_entity
      end

      @report = AuditEvent.compliance_report(
        tenant_id: tenant_id,
        start_date: @start_date,
        end_date: @end_date
      )

      log_admin_action("compliance_report_generated", { tenant_id: tenant_id })

      respond_to do |format|
        format.html { render :report }
        format.json { render json: @report }
        format.pdf { generate_pdf_report(@report) }
      end
    end

    # =========================================================================
    # GET /admin/compliance/search
    # Advanced search across audit logs
    # =========================================================================
    def search
      @results = AuditEvent.where(nil)

      @results = @results.where("action ILIKE ?", "%#{params[:action_query]}%") if params[:action_query].present?
      @results = @results.for_tenant(params[:tenant_id]) if params[:tenant_id].present?
      @results = @results.for_user(params[:user_id]) if params[:user_id].present?
      @results = @results.by_type(params[:event_type]) if params[:event_type].present?
      @results = @results.in_range(@start_date, @end_date)
      @results = @results.order(created_at: :desc).limit(500)

      render json: {
        count: @results.count,
        results: @results.map(&:to_audit_hash)
      }
    end

    private

    # =========================================================================
    # AUTHENTICATION
    # =========================================================================

    def authenticate_admin!
      unless current_user&.admin?
        log_access_denied
        respond_to do |format|
          format.html do
            flash[:alert] = "Admin access required"
            redirect_to root_path
          end
          format.json do
            render json: { error: "Forbidden" }, status: :forbidden
          end
        end
      end
    end

    def current_user
      @current_user ||= User.find_by(id: session[:user_id])
    end

    # =========================================================================
    # FILTERS
    # =========================================================================

    def set_date_range
      @start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : 30.days.ago.to_date
      @end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.current
    rescue ArgumentError
      @start_date = 30.days.ago.to_date
      @end_date = Date.current
    end

    def filtered_audit_events
      scope = AuditEvent.in_range(@start_date.beginning_of_day, @end_date.end_of_day)
      scope = scope.for_tenant(params[:tenant_id]) if params[:tenant_id].present?
      scope = scope.for_user(params[:user_id]) if params[:user_id].present?
      scope = scope.by_type(params[:event_type]) if params[:event_type].present?
      scope
    end

    def filtered_paper_trail_versions
      scope = PaperTrail::Version.where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
      scope = scope.where(whodunnit: params[:user_id]) if params[:user_id].present?
      scope = scope.where(item_type: params[:item_type]) if params[:item_type].present?
      scope
    end

    # =========================================================================
    # STATS & VERIFICATION
    # =========================================================================

    def calculate_stats
      events = AuditEvent.in_range(@start_date.beginning_of_day, @end_date.end_of_day)

      {
        total_events: events.count,
        billing_events: events.billing_events.count,
        subscription_events: events.subscription_events.count,
        admin_events: events.admin_events.count,
        unique_tenants: events.distinct.count(:tenant_id),
        unique_users: events.distinct.count(:user_id)
      }
    end

    def quick_chain_verification
      last_event = AuditEvent.order(sequence: :desc).first
      return { status: "empty", message: "No audit events" } unless last_event

      sample_check = last_event.verify_signature

      {
        status: sample_check ? "healthy" : "warning",
        last_sequence: last_event.sequence,
        last_verified: last_event.created_at.utc.iso8601,
        signature_valid: sample_check
      }
    end

    # =========================================================================
    # EXPORT HELPERS
    # =========================================================================

    def generate_csv(events)
      require "csv"

      CSV.generate(headers: true) do |csv|
        csv << %w[sequence event_type action tenant_id user_id created_at signature_hash verified]

        events.find_each do |event|
          csv << [
            event.sequence,
            event.event_type,
            event.action,
            event.tenant_id,
            event.user_id,
            event.created_at.utc.iso8601,
            event.signature_hash,
            event.verify_signature
          ]
        end
      end
    end

    def generate_pdf_report(report)
      # Placeholder for PDF generation (requires prawn gem)
      render plain: "PDF generation requires prawn gem", status: :not_implemented
    end

    def audit_json_response
      {
        stats: @stats,
        chain_status: @chain_status,
        events: @audit_events.map(&:to_audit_hash),
        pagination: {
          current_page: @audit_events.current_page,
          total_pages: @audit_events.total_pages,
          total_count: @audit_events.total_count
        }
      }
    end

    # =========================================================================
    # AUDIT LOGGING
    # =========================================================================

    def log_admin_action(action, metadata = {})
      AuditLogger.admin_action(
        tenant: nil,
        user: current_user,
        action: "compliance.#{action}",
        metadata: metadata.merge(
          ip_address: request.remote_ip,
          timestamp: Time.current.utc.iso8601
        )
      )
    rescue StandardError => e
      Rails.logger.error "[Admin Audit] Failed: #{e.message}"
    end

    def log_access_denied
      Rails.logger.warn "[Admin] Access denied: user=#{current_user&.id} path=#{request.path}"
    end
  end
end
