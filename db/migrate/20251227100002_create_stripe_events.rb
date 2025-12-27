# frozen_string_literal: true

# =============================================================================
# StripeEvent Model Migration
# =============================================================================
# Tracks processed Stripe webhook events for idempotency
# Ensures each event is processed exactly once across all instances
# FDA 21 CFR Part 11 Compliant - Immutable audit trail of all Stripe events
#
# Run: bin/rails db:migrate
# =============================================================================

class CreateStripeEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :stripe_events do |t|
      # Stripe event ID (evt_xxx) - unique identifier
      t.string :stripe_event_id, null: false

      # Event type (checkout.session.completed, invoice.paid, etc.)
      t.string :event_type

      # Associated tenant (if applicable)
      t.bigint :tenant_id

      # Processing status
      t.string :processing_status, default: "processed"

      # Additional event metadata (livemode, api_version, etc.)
      t.jsonb :metadata, default: {}

      # When the event was processed
      t.datetime :processed_at, null: false

      t.timestamps
    end

    # Unique constraint on Stripe event ID for idempotency
    add_index :stripe_events, :stripe_event_id, unique: true

    # Query indexes
    add_index :stripe_events, :event_type
    add_index :stripe_events, :tenant_id
    add_index :stripe_events, :processed_at
    add_index :stripe_events, [:tenant_id, :processed_at]
    add_index :stripe_events, [:event_type, :processed_at]

    # Optional: Foreign key to tenants (soft - don't enforce for orphaned events)
    # add_foreign_key :stripe_events, :tenants, on_delete: :nullify
  end
end
