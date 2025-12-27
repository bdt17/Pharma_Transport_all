class Shipment < ApplicationRecord
  # FDA 21 CFR Part 11 Audit Trail
  has_paper_trail meta: { tenant_id: :tenant_id },
                  versions: { class_name: "PaperTrail::Version" }

  belongs_to :tenant
  belongs_to :vehicle, optional: true
  has_many :temperature_events, dependent: :destroy
  has_many :geofence_events, dependent: :destroy
  has_many :alerts, dependent: :destroy

  validates :tracking_number, presence: true, uniqueness: true

  enum :status, {
    pending: 'pending',
    in_transit: 'in_transit',
    delivered: 'delivered',
    cancelled: 'cancelled',
    exception: 'exception'
  }, prefix: true

  scope :active, -> { where(status: [:pending, :in_transit]) }
  scope :with_excursions, -> { joins(:temperature_events).where(temperature_events: { excursion: true }).distinct }

  before_validation :generate_tracking_number, on: :create

  def temperature_compliant?
    return true if temperature_events.empty?
    temperature_events.where(excursion: true).none?
  end

  def current_temperature
    temperature_events.order(recorded_at: :desc).first&.temperature
  end

  def update_location(lat, lng)
    update(current_lat: lat, current_lng: lng)
  end

  def duration_hours
    return nil unless actual_pickup_at
    end_time = actual_delivery_at || Time.current
    ((end_time - actual_pickup_at) / 1.hour).round(1)
  end

  private

  def generate_tracking_number
    return if tracking_number.present?
    self.tracking_number = "PT-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end
end
