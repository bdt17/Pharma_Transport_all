# frozen_string_literal: true

# =============================================================================
# AuditEvent Model
# =============================================================================
# FDA 21 CFR Part 11 compliant immutable audit log entries
# Records subscription changes, billing actions, and admin operations
#
# Fields:
#   - event_type     : Type of event (subscription.created, billing.payment_failed, etc.)
#   - user_id        : User who performed action (nil for system/webhook events)
#   - tenant_id      : Associated tenant
#   - resource_type  : Type of resource affected (Tenant, Subscription, etc.)
#   - resource_id    : ID of affected resource
#   - action         : Specific action taken
#   - changes        : JSONB of before/after state
#   - metadata       : Additional context (IP, user agent, etc.)
#   - signature_hash : SHA256 hash for tamper detection
#   - previous_hash  : Hash of previous record (chain integrity)
#   - sequence       : Monotonic sequence number
#
# Deploy: Render + PostgreSQL
# =============================================================================

class AuditEvent < ApplicationRecord
  # ===========================================================================
  # ASSOCIATIONS
  # ===========================================================================
  belongs_to :tenant, optional: true
  belongs_to :user, optional: true

  # ===========================================================================
  # VALIDATIONS
  # ===========================================================================
  validates :event_type, presence: true
  validates :action, presence: true
  validates :signature_hash, presence: true
  validates :sequence, presence: true, uniqueness: true

  # ===========================================================================
  # CALLBACKS
  # ===========================================================================
  before_validation :set_sequence_and_hash, on: :create

  # ===========================================================================
  # SCOPES
  # ===========================================================================
  scope :for_tenant, ->(tenant_id) { where(tenant_id: tenant_id) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :by_type, ->(event_type) { where(event_type: event_type) }
  scope :recent, -> { order(created_at: :desc) }
  scope :in_range, ->(start_at, end_at) { where(created_at: start_at..end_at) }
  scope :billing_events, -> { where("event_type LIKE ?", "billing.%") }
  scope :subscription_events, -> { where("event_type LIKE ?", "subscription.%") }
  scope :admin_events, -> { where("event_type LIKE ?", "admin.%") }

  # ===========================================================================
  # FDA 21 CFR PART 11 IMMUTABILITY
  # ===========================================================================
  before_update { raise ActiveRecord::ReadOnlyRecord, "AuditEvents are immutable (FDA 21 CFR Part 11)" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "AuditEvents cannot be deleted (FDA 21 CFR Part 11)" }

  # ===========================================================================
  # EVENT TYPES
  # ===========================================================================
  EVENT_TYPES = {
    # Subscription events
    "subscription.created" => "New subscription created",
    "subscription.activated" => "Subscription activated",
    "subscription.updated" => "Subscription plan changed",
    "subscription.canceled" => "Subscription cancelled",
    "subscription.reactivated" => "Subscription reactivated",

    # Billing events
    "billing.checkout_started" => "Checkout session initiated",
    "billing.checkout_completed" => "Checkout completed successfully",
    "billing.checkout_cancelled" => "Checkout cancelled by user",
    "billing.payment_succeeded" => "Payment processed successfully",
    "billing.payment_failed" => "Payment failed",
    "billing.invoice_created" => "Invoice generated",
    "billing.refund_issued" => "Refund processed",

    # Admin events
    "admin.tenant_created" => "Tenant account created",
    "admin.tenant_updated" => "Tenant settings modified",
    "admin.tenant_suspended" => "Tenant account suspended",
    "admin.user_created" => "User account created",
    "admin.user_updated" => "User account modified",
    "admin.api_key_created" => "API key generated",
    "admin.api_key_revoked" => "API key revoked",

    # Access events
    "access.login" => "User logged in",
    "access.logout" => "User logged out",
    "access.denied" => "Access denied (subscription required)"
  }.freeze

  # ===========================================================================
  # CLASS METHODS
  # ===========================================================================

  # Record a new audit event
  def self.record!(event_type:, action:, tenant: nil, user: nil, resource: nil, changes: {}, metadata: {})
    create!(
      event_type: event_type,
      action: action,
      tenant: tenant,
      user: user,
      resource_type: resource&.class&.name,
      resource_id: resource&.id,
      changes: changes,
      metadata: metadata.merge(
        recorded_at: Time.current.utc.iso8601,
        environment: Rails.env
      )
    )
  end

  # Verify chain integrity for FDA compliance
  def self.verify_chain(tenant_id: nil, start_seq: nil, end_seq: nil)
    scope = all
    scope = scope.where(tenant_id: tenant_id) if tenant_id
    scope = scope.where("sequence >= ?", start_seq) if start_seq
    scope = scope.where("sequence <= ?", end_seq) if end_seq

    events = scope.order(:sequence).to_a
    return { valid: true, checked: 0, errors: [] } if events.empty?

    errors = []

    events.each_with_index do |event, index|
      # Verify signature hash
      expected_hash = event.compute_signature_hash
      unless event.signature_hash == expected_hash
        errors << {
          sequence: event.sequence,
          error: "Signature hash mismatch - possible tampering detected",
          expected: expected_hash,
          actual: event.signature_hash
        }
      end

      # Verify chain link (skip first)
      if index > 0
        prev_event = events[index - 1]
        unless event.previous_hash == prev_event.signature_hash
          errors << {
            sequence: event.sequence,
            error: "Chain broken - previous hash mismatch",
            expected: prev_event.signature_hash,
            actual: event.previous_hash
          }
        end
      end
    end

    {
      valid: errors.empty?,
      checked: events.size,
      first_sequence: events.first&.sequence,
      last_sequence: events.last&.sequence,
      errors: errors
    }
  end

  # Get audit report for FDA inspection
  def self.compliance_report(tenant_id:, start_date:, end_date:)
    events = for_tenant(tenant_id).in_range(start_date, end_date).order(:sequence)

    {
      tenant_id: tenant_id,
      report_generated_at: Time.current.utc.iso8601,
      date_range: { start: start_date.iso8601, end: end_date.iso8601 },
      total_events: events.count,
      events_by_type: events.group(:event_type).count,
      chain_verification: verify_chain(tenant_id: tenant_id),
      events: events.map(&:to_audit_hash)
    }
  end

  # ===========================================================================
  # INSTANCE METHODS
  # ===========================================================================

  # Compute signature hash for this record
  def compute_signature_hash
    data = [
      event_type.to_s,
      action.to_s,
      tenant_id.to_s,
      user_id.to_s,
      resource_type.to_s,
      resource_id.to_s,
      changes.to_json,
      previous_hash.to_s,
      sequence.to_s,
      created_at&.utc&.iso8601.to_s
    ].join("|")

    Digest::SHA256.hexdigest(data)
  end

  # Verify this record's integrity
  def verify_signature
    signature_hash == compute_signature_hash
  end

  # Export for FDA compliance report
  def to_audit_hash
    {
      sequence: sequence,
      event_type: event_type,
      action: action,
      description: EVENT_TYPES[event_type] || event_type,
      tenant_id: tenant_id,
      user_id: user_id,
      resource: { type: resource_type, id: resource_id },
      changes: changes,
      metadata: metadata,
      timestamp: created_at.utc.iso8601,
      signature_valid: verify_signature,
      signature_hash: signature_hash
    }
  end

  private

  # ===========================================================================
  # HASH CHAIN GENERATION
  # ===========================================================================

  def set_sequence_and_hash
    self.sequence = next_sequence
    self.previous_hash = last_signature_hash
    self.created_at ||= Time.current
    self.signature_hash = compute_signature_hash
  end

  def next_sequence
    (AuditEvent.maximum(:sequence) || 0) + 1
  end

  def last_signature_hash
    AuditEvent.order(sequence: :desc).first&.signature_hash
  end
end
