# frozen_string_literal: true

# =============================================================================
# FDA 21 CFR Part 11 Compliance Tasks
# =============================================================================
# Audit chain verification and compliance reporting
# Run daily via Render cron job
# =============================================================================

namespace :fda do
  desc "Verify audit chain integrity (FDA 21 CFR Part 11)"
  task verify_audit_chain: :environment do
    puts "[FDA] Starting audit chain verification..."
    puts "[FDA] Timestamp: #{Time.current.utc.iso8601}"

    begin
      result = AuditEvent.verify_chain

      puts "[FDA] Chain Status: #{result[:valid] ? 'VALID' : 'INVALID'}"
      puts "[FDA] Records Checked: #{result[:checked]}"
      puts "[FDA] First Sequence: #{result[:first_sequence]}"
      puts "[FDA] Last Sequence: #{result[:last_sequence]}"

      if result[:errors].any?
        puts "[FDA] ERRORS DETECTED:"
        result[:errors].each do |error|
          puts "[FDA]   Sequence #{error[:sequence]}: #{error[:error]}"
        end

        # Alert on chain integrity failure
        Rails.logger.error "[FDA CRITICAL] Audit chain integrity failure detected!"

        # Exit with error code for monitoring
        exit 1
      else
        puts "[FDA] All records verified successfully"
        Rails.logger.info "[FDA] Audit chain verification passed: #{result[:checked]} records"
      end
    rescue StandardError => e
      puts "[FDA] ERROR: #{e.message}"
      Rails.logger.error "[FDA] Verification failed: #{e.message}"
      exit 1
    end
  end

  desc "Generate FDA compliance report for a tenant"
  task :compliance_report, [:tenant_id, :start_date, :end_date] => :environment do |_t, args|
    tenant_id = args[:tenant_id] || ENV["TENANT_ID"]
    start_date = Date.parse(args[:start_date] || 30.days.ago.to_s)
    end_date = Date.parse(args[:end_date] || Date.current.to_s)

    unless tenant_id
      puts "Usage: rake fda:compliance_report[tenant_id,start_date,end_date]"
      puts "  Or set TENANT_ID environment variable"
      exit 1
    end

    puts "[FDA] Generating compliance report..."
    puts "[FDA] Tenant: #{tenant_id}"
    puts "[FDA] Period: #{start_date} to #{end_date}"

    report = AuditEvent.compliance_report(
      tenant_id: tenant_id,
      start_date: start_date.beginning_of_day,
      end_date: end_date.end_of_day
    )

    # Output as JSON for processing
    puts JSON.pretty_generate(report)

    # Save to file
    filename = "fda_compliance_report_#{tenant_id}_#{Date.current}.json"
    File.write(Rails.root.join("tmp", filename), JSON.pretty_generate(report))
    puts "[FDA] Report saved to tmp/#{filename}"
  end

  desc "Export audit events for FDA inspection"
  task :export_audit_events, [:tenant_id, :days] => :environment do |_t, args|
    tenant_id = args[:tenant_id] || ENV["TENANT_ID"]
    days = (args[:days] || 90).to_i

    unless tenant_id
      puts "Usage: rake fda:export_audit_events[tenant_id,days]"
      exit 1
    end

    puts "[FDA] Exporting audit events..."

    events = AuditEvent
      .for_tenant(tenant_id)
      .where("created_at > ?", days.days.ago)
      .order(:sequence)

    filename = "fda_audit_export_#{tenant_id}_#{Date.current}.csv"
    filepath = Rails.root.join("tmp", filename)

    CSV.open(filepath, "w") do |csv|
      csv << %w[sequence event_type action user_id created_at signature_hash verified]
      events.find_each do |event|
        csv << [
          event.sequence,
          event.event_type,
          event.action,
          event.user_id,
          event.created_at.utc.iso8601,
          event.signature_hash,
          event.verify_signature
        ]
      end
    end

    puts "[FDA] Exported #{events.count} events to tmp/#{filename}"
  end

  desc "Cleanup old Stripe events (keep 90 days for FDA)"
  task cleanup_stripe_events: :environment do
    puts "[FDA] Cleaning up old Stripe events..."

    count = StripeEvent.cleanup_old_events!(days: 90)
    puts "[FDA] Removed #{count} events older than 90 days"

    Rails.logger.info "[FDA] Stripe event cleanup: #{count} records removed"
  end
end
