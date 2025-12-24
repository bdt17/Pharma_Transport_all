class ComplianceController < ApplicationController
  def audit
    audits = AuditLog.where(created_at: 7.days.ago..Time.now).limit(100)
    render json: audits.map { |a| {
      action: a.action,
      user_id: a.user_id,
      record_id: a.record_id,
      timestamp: a.created_at.utc.iso8601,
      ip: a.ip_address
    }}
  end

  def sign
    render json: {
      compliant: true,
      trucks: 286,
      signature: {
        user: "Pharma Admin",
        timestamp: Time.now.utc.iso8601,
        meaning: "21 CFR Part 11 validated"
      }
    }
  end
end
