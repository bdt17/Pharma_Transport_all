# frozen_string_literal: true

# =============================================================================
# Database Seeds - Pharma Transport
# =============================================================================
# FDA 21 CFR Part 11 Compliant | Stripe Live Mode Ready
#
# Run: rails db:seed
# =============================================================================

puts "[Seeds] Starting database seeding..."

# =============================================================================
# DEMO TENANT
# =============================================================================
puts "[Seeds] Creating demo tenant..."

demo_tenant = Tenant.find_or_create_by!(subdomain: "demo") do |t|
  t.name = "Demo Cold Chain Inc."
  t.status = "active"
  t.plan = "smb"
  t.subscription_status = "active"
  t.billing_email = "demo@pharmatransport.io"
end

puts "[Seeds] Demo tenant: #{demo_tenant.id} (#{demo_tenant.subdomain})"

# =============================================================================
# ADMIN USER
# =============================================================================
puts "[Seeds] Creating admin user..."

admin_user = User.find_or_create_by!(email: "admin@pharmatransport.io") do |u|
  u.tenant = demo_tenant
  u.password_digest = BCrypt::Password.create("SecureAdmin123!")
  u.role = "admin"
  u.active = true
end

puts "[Seeds] Admin user: #{admin_user.id} (#{admin_user.email})"

# =============================================================================
# API KEY
# =============================================================================
puts "[Seeds] Creating demo API key..."

api_key = ApiKey.find_or_create_by!(tenant: demo_tenant, name: "Demo API Key") do |k|
  k.active = true
  k.permissions = { read: true, write: true }
end

puts "[Seeds] API Key: #{api_key.key_prefix}..."

# =============================================================================
# SAMPLE SHIPMENTS
# =============================================================================
puts "[Seeds] Creating sample shipments..."

3.times do |i|
  shipment = Shipment.find_or_create_by!(
    tenant: demo_tenant,
    tracking_number: "PFZ-DEMO-#{1000 + i}"
  ) do |s|
    s.origin = ["Indianapolis, IN", "Memphis, TN", "Louisville, KY"][i]
    s.destination = ["Boston, MA", "New York, NY", "Philadelphia, PA"][i]
    s.status = ["in_transit", "delivered", "in_transit"][i]
    s.temperature_min = 2.0
    s.temperature_max = 8.0
    s.cargo_type = "vaccine"
  end

  # Temperature events
  if shipment.status == "in_transit"
    5.times do |j|
      TemperatureEvent.create!(
        tenant: demo_tenant,
        shipment: shipment,
        temperature: rand(3.0..6.0).round(2),
        humidity: rand(40.0..60.0).round(1),
        recorded_at: j.hours.ago,
        excursion: false
      )
    end
  end

  puts "[Seeds] Shipment: #{shipment.tracking_number} (#{shipment.status})"
end

# =============================================================================
# AUDIT LOG ENTRY
# =============================================================================
puts "[Seeds] Creating initial audit event..."

AuditLog.log(
  tenant: demo_tenant,
  action: "system.database_seeded",
  resource: demo_tenant,
  user: admin_user,
  metadata: {
    source: "db/seeds.rb",
    timestamp: Time.current.utc.iso8601,
    environment: Rails.env
  }
) rescue nil # Skip if AuditLog not ready

puts "[Seeds] Database seeding complete!"
puts ""
puts "=" * 60
puts "DEMO CREDENTIALS"
puts "=" * 60
puts "Tenant:    demo"
puts "Email:     admin@pharmatransport.io"
puts "Password:  SecureAdmin123!"
puts "API Key:   #{api_key&.key_prefix}... (see rails console)"
puts "=" * 60
