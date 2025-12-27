# frozen_string_literal: true

# StripeEvent model for webhook idempotency
# Prevents duplicate processing of Stripe webhook events across instances
# Required for FDA 21 CFR Part 11 - ensures exactly-once event processing

class CreateStripeEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :stripe_events do |t|
      t.string :stripe_event_id, null: false
      t.string :event_type
      t.string :tenant_id
      t.string :processing_status, default: "processed"
      t.jsonb :metadata, default: {}
      t.datetime :processed_at, null: false

      t.timestamps
    end

    add_index :stripe_events, :stripe_event_id, unique: true
    add_index :stripe_events, :event_type
    add_index :stripe_events, :tenant_id
    add_index :stripe_events, :processed_at
    add_index :stripe_events, [:tenant_id, :processed_at]
  end
end
