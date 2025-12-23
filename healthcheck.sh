#!/bin/bash
BASE_URL="https://pharma-dashboard-s4g5.onrender.com"
endpoints=(
  "/" 
  "/dashboard" 
  "/vehicles" 
  "/map" 
  "/audit_events" 
  "/geofences" 
  "/sensor_readings" 
  "/electronic_signatures" 
  "/dea_shipments" 
  "/transport_anomalies" 
  "/reports"
  "/api/v1/realtime"     # Phase 8 GPS
  "/billing"             # Phase 9 Stripe
)

echo "🚚 PHARMA TRANSPORT v9.0 - $(date)"
echo "🌐 PRODUCTION: $BASE_URL"
echo "========================================"

failed=0
for endpoint in "${endpoints[@]}"; do
  # PRODUCTION CURL: -fsSL (fail fast, silent, location, show errors)
  status=$(curl -fsSL -w "%{http_code}" -o /dev/null "$BASE_URL$endpoint" 2>/dev/null)
  if [ "$status" = "200" ]; then
    echo "✅ $endpoint [200]"
  else
    echo "❌ $endpoint [$status]"
    ((failed++))
  fi
done

# Health endpoint with content preview
echo "🌐 Health:"
health_content=$(curl -fsSL "$BASE_URL/health" 2>/dev/null | head -1)
echo "$health_content"

if [ $failed -eq 0 ]; then
  echo "🎉 $(( ${#endpoints[@]} ))/13 ENDPOINTS PERFECT!"
else
  echo "⚠️  $failed/$(( ${#endpoints[@]} )) endpoints failed"
fi
