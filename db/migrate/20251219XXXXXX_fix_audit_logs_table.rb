class FixAuditLogsTable < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      add_column :audit_logs, :auditable_type, :string unless column_exists?(:audit_logs, :auditable_type)
      add_column :audit_logs, :auditable_id, :bigint unless column_exists?(:audit_logs, :auditable_id)
      add_column :audit_logs, :event, :string unless column_exists?(:audit_logs, :event)
      add_column :audit_logs, :data, :jsonb, default: {} unless column_exists?(:audit_logs, :data)
      add_index :audit_logs, [:auditable_type, :auditable_id] unless index_exists?(:audit_logs, [:auditable_type, :auditable_id])
    end
  end
end
