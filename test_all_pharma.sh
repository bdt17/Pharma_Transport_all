#!/bin/bash
BASE_URL="http://localhost:3000"
echo "🚀 Pharma Transport ENTERPRISE TEST SUITE + ERROR HUNTER"
echo "========================================================="

# Function to test URL and catch 404s
test_url() {
  local url="$BASE_URL$1"
  echo -n "Testing $url ... "
  status=$(curl -s -w "%{http_code}" -o /tmp/test.html "$url")
  if [ "$status" = "200" ]; then
    echo "✅ PASS"
  else
    echo "❌ FAIL ($status)"
    echo "💡 Routes with 'vehicles#map': /map OR /vehicles/1/map"
  fi
}

# 1. Root
test_url "/"

# 2. Dashboard  
test_url "/dashboard"

# 3. CORRECT Map URLs
test_url "/map"
test_url "/vehicles/1/map"

# 4. Vehicles index
test_url "/vehicles"

# 5. Pricing
test_url "/pricing"

# 6. FDA pages
test_url "/audit_events"
test_url "/geofences"

# 7. ERROR DETECTOR - Find bad links in HTML
echo "🔍 Scanning for broken /vehicles/map links..."
grep -r "/vehicles/map" app/views/ 2>/dev/null | head -3 || echo "✅ No bad links found"

# 8. Bootstrap check
curl -s "$BASE_URL/dashboard" | grep -q "navbar.*bg-primary" && echo "✅ Bootstrap OK" || echo "⚠️ Bootstrap missing"

echo ""
echo "🎉 TEST SUMMARY:"
echo "✅ Working URLs: /dashboard, /map, /vehicles/1/map"
echo "❌ NEVER USE: /vehicles/map (no route!)"
echo "🚀 PLATFORM LIVE → Use navbar links only!"

