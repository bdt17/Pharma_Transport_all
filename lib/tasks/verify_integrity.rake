# frozen_string_literal: true

# =============================================================================
# Verify Integrity Rake Tasks
# =============================================================================
# FDA 21 CFR Part 11 Compliant Audit Chain Verification
# Validates checksum consistency across all AuditEvent records
#
# Usage:
#   rails integrity:verify              - Full chain verification
#   rails integrity:verify_tenant[id]   - Verify specific tenant
#   rails integrity:repair              - Attempt to repair chain issues
#   rails integrity:report              - Generate detailed report
# =============================================================================

namespace :integrity do
  desc "Verify FDA audit chain integrity across all records"
  task verify: :environment do
    puts "[Integrity] Starting full audit chain verification..."
    puts "[Integrity] Timestamp: #{Time.current.utc.iso8601}"
    puts ""

    result = verify_full_chain

    display_verification_result(result)
    exit(result[:valid] ? 0 : 1)
  end

  desc "Verify audit chain for specific tenant"
  task :verify_tenant, [:tenant_id] => :environment do |_t, args|
    tenant_id = args[:tenant_id]

    unless tenant_id
      puts "Usage: rails integrity:verify_tenant[TENANT_ID]"
      exit 1
    end

    puts "[Integrity] Verifying audit chain for tenant #{tenant_id}..."

    result = AuditEvent.verify_chain(tenant_id: tenant_id)
    display_verification_result(result)

    exit(result[:valid] ? 0 : 1)
  end

  desc "Verify with detailed checksum comparison"
  task verify_checksums: :environment do
    puts "[Integrity] Performing detailed checksum verification..."
    puts ""

    total = AuditEvent.count
    verified = 0
    failed = []
    batch_size = 1000

    AuditEvent.order(:sequence).find_in_batches(batch_size: batch_size) do |batch|
      batch.each do |event|
        expected = event.compute_signature_hash
        actual = event.signature_hash

        if expected == actual
          verified += 1
        else
          failed << {
            sequence: event.sequence,
            id: event.id,
            expected: expected,
            actual: actual,
            created_at: event.created_at.utc.iso8601
          }
        end
      end

      print "\r[Integrity] Verified #{verified}/#{total} records..."
    end

    puts ""
    puts ""

    if failed.empty?
      puts "[Integrity] SUCCESS: All #{verified} records passed checksum verification"
    else
      puts "[Integrity] FAILURE: #{failed.count} records failed verification"
      puts ""
      puts "Failed records:"
      failed.first(20).each do |f|
        puts "  Sequence #{f[:sequence]} (ID: #{f[:id]})"
        puts "    Expected: #{f[:expected][0..15]}..."
        puts "    Actual:   #{f[:actual][0..15]}..."
      end
      puts "  ... and #{failed.count - 20} more" if failed.count > 20
    end

    exit(failed.empty? ? 0 : 1)
  end

  desc "Verify chain link integrity (previous_hash connections)"
  task verify_chain_links: :environment do
    puts "[Integrity] Verifying chain link integrity..."
    puts ""

    broken_links = []
    prev_event = nil

    AuditEvent.order(:sequence).find_each do |event|
      if prev_event
        if event.previous_hash != prev_event.signature_hash
          broken_links << {
            sequence: event.sequence,
            expected_previous: prev_event.signature_hash,
            actual_previous: event.previous_hash,
            gap: event.sequence - prev_event.sequence
          }
        end
      end
      prev_event = event

      print "\r[Integrity] Checked through sequence #{event.sequence}..." if event.sequence % 1000 == 0
    end

    puts ""
    puts ""

    if broken_links.empty?
      puts "[Integrity] SUCCESS: All chain links verified"
    else
      puts "[Integrity] FAILURE: #{broken_links.count} broken chain links found"
      puts ""
      broken_links.first(10).each do |link|
        puts "  Sequence #{link[:sequence]}: Chain link broken (gap: #{link[:gap]})"
      end
    end

    exit(broken_links.empty? ? 0 : 1)
  end

  desc "Generate detailed integrity report"
  task report: :environment do
    puts "[Integrity] Generating detailed integrity report..."
    puts ""

    report = {
      generated_at: Time.current.utc.iso8601,
      total_records: AuditEvent.count,
      first_sequence: AuditEvent.minimum(:sequence),
      last_sequence: AuditEvent.maximum(:sequence),
      date_range: {
        first: AuditEvent.minimum(:created_at)&.utc&.iso8601,
        last: AuditEvent.maximum(:created_at)&.utc&.iso8601
      },
      by_event_type: AuditEvent.group(:event_type).count,
      by_tenant: AuditEvent.group(:tenant_id).count.transform_keys(&:to_s),
      chain_verification: AuditEvent.verify_chain,
      sequence_gaps: find_sequence_gaps,
      duplicate_sequences: find_duplicate_sequences
    }

    puts JSON.pretty_generate(report)

    # Save to file
    filename = "integrity_report_#{Date.current}.json"
    File.write(Rails.root.join("tmp", filename), JSON.pretty_generate(report))
    puts ""
    puts "[Integrity] Report saved to tmp/#{filename}"
  end

  desc "Attempt to repair audit chain issues (USE WITH CAUTION)"
  task repair: :environment do
    puts "[Integrity] WARNING: This task will attempt to repair audit chain issues"
    puts "[Integrity] This should only be used in development/staging"
    puts ""

    if Rails.env.production?
      puts "[Integrity] BLOCKED: Cannot run repair in production"
      puts "[Integrity] Contact support for production chain repairs"
      exit 1
    end

    print "Type 'REPAIR' to continue: "
    confirmation = STDIN.gets.chomp

    unless confirmation == "REPAIR"
      puts "[Integrity] Aborted"
      exit 1
    end

    puts ""
    puts "[Integrity] Repairing chain..."

    repaired = 0
    prev_event = nil

    AuditEvent.order(:sequence).find_each do |event|
      needs_repair = false

      # Check signature
      expected_sig = event.compute_signature_hash
      if event.signature_hash != expected_sig
        # Can't repair signature without changing data
        puts "[Integrity] Sequence #{event.sequence}: Signature mismatch (cannot auto-repair)"
      end

      # Check previous hash
      if prev_event && event.previous_hash != prev_event.signature_hash
        puts "[Integrity] Sequence #{event.sequence}: Repairing chain link"
        event.update_column(:previous_hash, prev_event.signature_hash)
        repaired += 1
      end

      prev_event = event
    end

    puts ""
    puts "[Integrity] Repair complete: #{repaired} records updated"
  end

  # ===========================================================================
  # HELPER METHODS
  # ===========================================================================

  def verify_full_chain
    AuditEvent.verify_chain
  rescue StandardError => e
    { valid: false, error: e.message }
  end

  def display_verification_result(result)
    puts "=" * 60
    puts "AUDIT CHAIN VERIFICATION RESULT"
    puts "=" * 60
    puts ""
    puts "Status:          #{result[:valid] ? 'VALID' : 'INVALID'}"
    puts "Records Checked: #{result[:checked] || 0}"
    puts "First Sequence:  #{result[:first_sequence] || 'N/A'}"
    puts "Last Sequence:   #{result[:last_sequence] || 'N/A'}"
    puts ""

    if result[:errors]&.any?
      puts "ERRORS DETECTED:"
      result[:errors].first(10).each do |error|
        puts "  Sequence #{error[:sequence]}: #{error[:error]}"
      end
      puts "  ... and #{result[:errors].count - 10} more" if result[:errors].count > 10
    end

    puts ""
    puts "=" * 60
  end

  def find_sequence_gaps
    gaps = []
    sequences = AuditEvent.order(:sequence).pluck(:sequence)

    sequences.each_cons(2) do |a, b|
      if b - a > 1
        gaps << { from: a, to: b, missing_count: b - a - 1 }
      end
    end

    gaps
  end

  def find_duplicate_sequences
    AuditEvent.group(:sequence).having("COUNT(*) > 1").count
  end
end
