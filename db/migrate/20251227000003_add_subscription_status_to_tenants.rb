# frozen_string_literal: true

# Add subscription_status to tenants for Stripe webhook state management
# Tracks: active, past_due, unpaid, canceled, trialing, incomplete

class AddSubscriptionStatusToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :subscription_status, :string, default: "active"
    add_index :tenants, :subscription_status
  end
end
