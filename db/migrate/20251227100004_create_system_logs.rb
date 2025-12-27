# frozen_string_literal: true

# =============================================================================
# CreateSystemLogs Migration
# =============================================================================
# FDA 21 CFR Part 11 Compliant system logging table
# Records operational events, job executions, and system health metrics
# =============================================================================

class CreateSystemLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :system_logs do |t|
      t.string :log_type, null: false
      t.string :severity, null: false, default: "info"
      t.text :message, null: false
      t.jsonb :metadata, default: {}
      t.datetime :recorded_at, null: false

      t.timestamps
    end

    add_index :system_logs, :log_type
    add_index :system_logs, :severity
    add_index :system_logs, :recorded_at
    add_index :system_logs, :created_at
    add_index :system_logs, [:log_type, :severity]
    add_index :system_logs, [:severity, :created_at]

    # Partial index for quick error lookups
    add_index :system_logs, :created_at,
              where: "severity IN ('error', 'critical')",
              name: "index_system_logs_on_errors"
  end
end
