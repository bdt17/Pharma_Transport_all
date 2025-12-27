# frozen_string_literal: true

# Add Stripe billing columns to Tenants
# Supports multi-tenant subscription management
class AddStripeToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :stripe_customer_id, :string
    add_column :tenants, :stripe_subscription_id, :string
    add_column :tenants, :subscription_status, :string, default: "trialing"
    add_column :tenants, :subscription_plan, :string, default: "free"
    add_column :tenants, :current_period_end, :datetime
    add_column :tenants, :trial_ends_at, :datetime
    add_column :tenants, :cancel_at_period_end, :boolean, default: false
    add_column :tenants, :canceled_at, :datetime
    add_column :tenants, :billing_email, :string
    add_column :tenants, :last_payment_at, :datetime
    add_column :tenants, :payment_failed_count, :integer, default: 0

    add_index :tenants, :stripe_customer_id, unique: true
    add_index :tenants, :stripe_subscription_id, unique: true
    add_index :tenants, :subscription_status
    add_index :tenants, :subscription_plan
  end
end
