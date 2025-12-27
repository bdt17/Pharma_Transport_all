class TemperatureEvent < ApplicationRecord
  # FDA 21 CFR Part 11 Audit Trail
  has_paper_trail meta: { tenant_id: :tenant_id },
                  versions: { class_name: "PaperTrail::Version" }

  belongs_to :shipment
  belongs_to :tenant

  validates :temperature, presence: true
  validates :recorded_at, presence: true

  enum :event_type, {
    reading: 'reading',
    excursion: 'excursion',
    alert: 'alert'
  }, prefix: true

  scope :excursions, -> { where(excursion: true) }
  scope :recent, -> { order(recorded_at: :desc) }
  scope :in_range, ->(start_at, end_at) { where(recorded_at: start_at..end_at) }

  before_save :check_excursion

  def self.record(shipment, temperature:, humidity: nil, lat: nil, lng: nil, sensor_id: nil, raw_data: {})
    create!(
      shipment: shipment,
      tenant: shipment.tenant,
      temperature: temperature,
      humidity: humidity,
      latitude: lat,
      longitude: lng,
      sensor_id: sensor_id,
      recorded_at: Time.current,
      raw_data: raw_data
    )
  end

  private

  def check_excursion
    return unless shipment

    if temperature < shipment.min_temp || temperature > shipment.max_temp
      self.excursion = true
      self.event_type = :excursion
    end
  end
end
