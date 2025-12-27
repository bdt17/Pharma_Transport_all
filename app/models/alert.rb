class Alert < ApplicationRecord
  # FDA 21 CFR Part 11 Audit Trail
  has_paper_trail meta: { tenant_id: :tenant_id },
                  versions: { class_name: "PaperTrail::Version" }

  belongs_to :tenant
  belongs_to :shipment, optional: true

  validates :alert_type, presence: true
  validates :title, presence: true

  enum :alert_type, {
    temperature: 'temperature',
    geofence: 'geofence',
    tamper: 'tamper',
    delay: 'delay',
    system: 'system'
  }, prefix: true

  enum :severity, {
    info: 'info',
    warning: 'warning',
    critical: 'critical'
  }, prefix: true

  enum :status, {
    open: 'open',
    acknowledged: 'acknowledged',
    resolved: 'resolved'
  }, prefix: true

  scope :active, -> { where(status: [:open, :acknowledged]) }
  scope :unacknowledged, -> { where(status: :open) }
  scope :recent, -> { order(created_at: :desc) }

  def acknowledge!(by:)
    update!(
      status: :acknowledged,
      acknowledged_by: by,
      acknowledged_at: Time.current
    )
  end

  def resolve!(by:, notes: nil)
    update!(
      status: :resolved,
      resolved_by: by,
      resolved_at: Time.current,
      resolution_notes: notes
    )
  end

  def self.create_temperature_alert(shipment, temperature:, threshold:, severity: :warning)
    create!(
      tenant: shipment.tenant,
      shipment: shipment,
      alert_type: :temperature,
      severity: severity,
      title: "Temperature excursion detected",
      message: "Temperature #{temperature}°C exceeded threshold #{threshold}°C",
      threshold_value: threshold,
      actual_value: temperature
    )
  end

  def self.create_geofence_alert(shipment, event_type:, geofence_name:, severity: :info)
    create!(
      tenant: shipment.tenant,
      shipment: shipment,
      alert_type: :geofence,
      severity: severity,
      title: "Geofence #{event_type}",
      message: "Shipment #{shipment.tracking_number} #{event_type} #{geofence_name}"
    )
  end
end
