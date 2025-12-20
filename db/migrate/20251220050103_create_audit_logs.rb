class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :event
      t.jsonb :data
      t.boolean :immutable

      t.timestamps
    end
  end
end
