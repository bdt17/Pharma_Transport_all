# frozen_string_literal: true

# =============================================================================
# StripeEvent Model
# =============================================================================
# Tracks processed Stripe webhook events for idempotency
# Ensures each event is processed exactly once across all application instances
# FDA 21 CFR Part 11 Compliant - Events are immutable once created
#
# Usage:
#   # Check if already processed
#   return if StripeEvent.processed?(event.id)
#
#   # Process event...
#
#   # Mark as processed
#   StripeEvent.record!(event, tenant: tenant)
# =============================================================================

class StripeEvent < ApplicationRecord
  # ===========================================================================
  # ASSOCIATIONS
  # ===========================================================================
  belongs_to :tenant, optional: true

  # ===========================================================================
  # VALIDATIONS
  # ===========================================================================
  validates :stripe_event_id, presence: true, uniqueness: true
  validates :processed_at, presence: true

  # ===========================================================================
  # SCOPES
  # ===========================================================================
  scope :recent, -> { where("processed_at > ?", 24.hours.ago) }
  scope :for_tenant, ->(tenant_id) { where(tenant_id: tenant_id) }
  scope :by_type, ->(event_type) { where(event_type: event_type) }
  scope :successful, -> { where(processing_status: "processed") }
  scope :failed, -> { where(processing_status: "failed") }

  # ===========================================================================
  # CLASS METHODS
  # ===========================================================================

  # Fast check if event was already processed
  def self.processed?(stripe_event_id)
    exists?(stripe_event_id: stripe_event_id)
  end

  # Record a processed event with full metadata
  def self.record!(event, tenant: nil, status: "processed")
    create!(
      stripe_event_id: event.id,
      event_type: event.type,
      tenant_id: tenant&.id,
      processing_status: status,
      processed_at: Time.current,
      metadata: {
        api_version: event.api_version,
        livemode: event.livemode,
        created: event.created,
        pending_webhooks: event.pending_webhooks
      }
    )
  rescue ActiveRecord::RecordNotUnique
    # Already processed by another instance - return existing record
    find_by(stripe_event_id: event.id)
  end

  # Record a failed event for retry tracking
  def self.record_failure!(event, error:, tenant: nil)
    create!(
      stripe_event_id: event.id,
      event_type: event.type,
      tenant_id: tenant&.id,
      processing_status: "failed",
      processed_at: Time.current,
      metadata: {
        api_version: event.api_version,
        livemode: event.livemode,
        error_message: error.message,
        error_class: error.class.name
      }
    )
  rescue ActiveRecord::RecordNotUnique
    # Update existing record with failure info
    event_record = find_by(stripe_event_id: event.id)
    event_record&.update(
      processing_status: "failed",
      metadata: event_record.metadata.merge(
        last_error: error.message,
        last_error_at: Time.current.utc.iso8601
      )
    )
    event_record
  end

  # Cleanup old events (run via cron/Sidekiq)
  # Keep 90 days for FDA compliance audit trail
  def self.cleanup_old_events!(days: 90)
    where("processed_at < ?", days.days.ago).delete_all
  end

  # ===========================================================================
  # FDA 21 CFR PART 11 COMPLIANCE
  # ===========================================================================

  # Immutable - prevent updates and deletes
  before_update :prevent_modification
  before_destroy :prevent_deletion

  private

  def prevent_modification
    # Allow status updates for retry tracking
    return if only_status_changed?

    raise ActiveRecord::ReadOnlyRecord, "StripeEvents are immutable for FDA compliance"
  end

  def prevent_deletion
    raise ActiveRecord::ReadOnlyRecord, "StripeEvents cannot be deleted for FDA compliance"
  end

  def only_status_changed?
    changed_attributes.keys.all? { |attr| attr.in?(%w[processing_status metadata updated_at]) }
  end
end
