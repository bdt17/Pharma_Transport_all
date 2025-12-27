# frozen_string_literal: true

# =============================================================================
# Complete Stripe Fields Migration for Tenants
# =============================================================================
# Adds all necessary fields for Stripe subscription management
# FDA 21 CFR Part 11 Compliant - Enables audit trail for billing changes
#
# Run: bin/rails db:migrate
# =============================================================================

class AddCompleteStripeFieldsToTenants < ActiveRecord::Migration[8.1]
  def change
    # Stripe Customer ID (cus_xxx)
    unless column_exists?(:tenants, :stripe_customer_id)
      add_column :tenants, :stripe_customer_id, :string
      add_index :tenants, :stripe_customer_id, unique: true
    end

    # Stripe Subscription ID (sub_xxx)
    unless column_exists?(:tenants, :stripe_subscription_id)
      add_column :tenants, :stripe_subscription_id, :string
      add_index :tenants, :stripe_subscription_id, unique: true
    end

    # Subscription status (mirrors Stripe: active, past_due, unpaid, canceled, trialing, incomplete)
    unless column_exists?(:tenants, :subscription_status)
      add_column :tenants, :subscription_status, :string, default: "active"
      add_index :tenants, :subscription_status
    end

    # Plan (free, smb, enterprise, pfizer)
    unless column_exists?(:tenants, :plan)
      add_column :tenants, :plan, :string, default: "free"
      add_index :tenants, :plan
    end

    # Billing email
    unless column_exists?(:tenants, :billing_email)
      add_column :tenants, :billing_email, :string
    end

    # Last successful payment timestamp
    unless column_exists?(:tenants, :last_payment_at)
      add_column :tenants, :last_payment_at, :datetime
    end

    # Trial end date
    unless column_exists?(:tenants, :trial_ends_at)
      add_column :tenants, :trial_ends_at, :datetime
    end

    # API call tracking for usage limits
    unless column_exists?(:tenants, :api_call_count)
      add_column :tenants, :api_call_count, :integer, default: 0
    end

    unless column_exists?(:tenants, :last_api_call_at)
      add_column :tenants, :last_api_call_at, :datetime
    end

    # Composite index for billing queries
    unless index_exists?(:tenants, [:subscription_status, :plan])
      add_index :tenants, [:subscription_status, :plan]
    end
  end
end
