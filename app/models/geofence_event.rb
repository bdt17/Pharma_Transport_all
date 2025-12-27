class GeofenceEvent < ApplicationRecord
  # FDA 21 CFR Part 11 Audit Trail
  has_paper_trail meta: { tenant_id: :tenant_id },
                  versions: { class_name: "PaperTrail::Version" }

  belongs_to :shipment
  belongs_to :tenant
  belongs_to :geofence, optional: true

  validates :event_type, presence: true
  validates :latitude, presence: true
  validates :longitude, presence: true
  validates :recorded_at, presence: true

  enum :event_type, {
    enter: 'enter',
    exit: 'exit',
    dwell: 'dwell'
  }, prefix: true

  scope :recent, -> { order(recorded_at: :desc) }
  scope :entries, -> { where(event_type: :enter) }
  scope :exits, -> { where(event_type: :exit) }

  def self.record_entry(shipment, geofence:, lat:, lng:)
    create!(
      shipment: shipment,
      tenant: shipment.tenant,
      geofence: geofence,
      geofence_name: geofence&.name,
      event_type: :enter,
      latitude: lat,
      longitude: lng,
      recorded_at: Time.current
    )
  end

  def self.record_exit(shipment, geofence:, lat:, lng:, dwell_seconds: nil)
    create!(
      shipment: shipment,
      tenant: shipment.tenant,
      geofence: geofence,
      geofence_name: geofence&.name,
      event_type: :exit,
      latitude: lat,
      longitude: lng,
      dwell_time_seconds: dwell_seconds,
      recorded_at: Time.current
    )
  end
end
