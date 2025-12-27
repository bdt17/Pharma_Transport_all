# frozen_string_literal: true

# =============================================================================
# Add FDA 21 CFR Part 11 Compliant Fields to AuditEvents
# =============================================================================
# Extends audit_events table with:
# - Hash chain integrity (signature_hash, previous_hash, sequence)
# - Proper associations (tenant_id, user_id)
# - Resource polymorphism (resource_type)
# - Change tracking (changes JSONB)
#
# Deploy: rails db:migrate
# =============================================================================

class AddFdaFieldsToAuditEvents < ActiveRecord::Migration[8.1]
  def change
    # Add event_type if not exists (may already have action)
    unless column_exists?(:audit_events, :event_type)
      add_column :audit_events, :event_type, :string
    end

    # Add tenant association
    unless column_exists?(:audit_events, :tenant_id)
      add_reference :audit_events, :tenant, foreign_key: true, index: true
    end

    # Add user association
    unless column_exists?(:audit_events, :user_id)
      add_reference :audit_events, :user, foreign_key: true, index: true
    end

    # Add resource polymorphism
    unless column_exists?(:audit_events, :resource_type)
      add_column :audit_events, :resource_type, :string
    end

    # Add changes JSONB for before/after state tracking
    unless column_exists?(:audit_events, :changes)
      add_column :audit_events, :changes, :jsonb, default: {}
    end

    # FDA 21 CFR Part 11 Hash Chain Fields
    unless column_exists?(:audit_events, :signature_hash)
      add_column :audit_events, :signature_hash, :string, null: false, default: ''
    end

    unless column_exists?(:audit_events, :previous_hash)
      add_column :audit_events, :previous_hash, :string
    end

    unless column_exists?(:audit_events, :sequence)
      add_column :audit_events, :sequence, :bigint
    end

    # Performance indexes for FDA compliance queries
    add_index :audit_events, :event_type unless index_exists?(:audit_events, :event_type)
    add_index :audit_events, :sequence, unique: true unless index_exists?(:audit_events, :sequence)
    add_index :audit_events, :signature_hash unless index_exists?(:audit_events, :signature_hash)
    add_index :audit_events, [:tenant_id, :sequence] unless index_exists?(:audit_events, [:tenant_id, :sequence])
    add_index :audit_events, [:tenant_id, :event_type, :created_at],
              name: 'idx_audit_events_tenant_type_time' unless index_exists?(:audit_events, [:tenant_id, :event_type, :created_at])
    add_index :audit_events, [:resource_type, :resource_id] unless index_exists?(:audit_events, [:resource_type, :resource_id])

    # Remove old actor column if exists (replaced by user_id)
    if column_exists?(:audit_events, :actor)
      remove_column :audit_events, :actor
    end
  end
end
