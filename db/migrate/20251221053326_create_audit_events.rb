class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events do |t|
      t.string :actor
      t.string :action
      t.integer :resource_id
      t.jsonb :metadata

      t.timestamps
    end
  end
end
