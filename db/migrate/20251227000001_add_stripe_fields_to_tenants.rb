# frozen_string_literal: true

# Phase 13: Add Stripe billing fields to Tenants
class AddStripeFieldsToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :stripe_customer_id, :string
    add_column :tenants, :stripe_subscription_id, :string
    add_column :tenants, :plan, :string, default: "free"
    add_column :tenants, :billing_email, :string
    add_column :tenants, :last_payment_at, :datetime

    add_index :tenants, :stripe_customer_id, unique: true
    add_index :tenants, :stripe_subscription_id, unique: true
    add_index :tenants, :plan
  end
end
