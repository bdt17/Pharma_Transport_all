# frozen_string_literal: true

# Phase 4: FDA 21 CFR Part 11 Audit Logging
# PaperTrail versions table for immutable record change tracking

class CreatePaperTrailVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :versions do |t|
      # Core PaperTrail columns
      t.string   :item_type, null: false
      t.bigint   :item_id,   null: false
      t.string   :event,     null: false
      t.string   :whodunnit
      t.jsonb    :object          # Previous state (for update/destroy)
      t.jsonb    :object_changes  # Changed attributes (for update)

      # FDA 21 CFR Part 11 compliance columns
      t.bigint   :tenant_id       # Multi-tenant isolation
      t.string   :ip_address      # Request origin for audit
      t.string   :user_agent      # Client identification
      t.string   :request_id      # Correlation ID
      t.jsonb    :metadata        # Additional compliance data

      t.datetime :created_at,     null: false
    end

    # Performance indexes
    add_index :versions, [:item_type, :item_id]
    add_index :versions, :created_at
    add_index :versions, :whodunnit
    add_index :versions, :tenant_id
    add_index :versions, :event

    # Composite indexes for common queries
    add_index :versions, [:tenant_id, :created_at]
    add_index :versions, [:item_type, :created_at]
    add_index :versions, [:tenant_id, :item_type, :item_id]

    # Foreign key for tenant (soft - allow orphaned records for audit integrity)
    # NOT using add_foreign_key to preserve audit history even if tenant deleted
  end
end
