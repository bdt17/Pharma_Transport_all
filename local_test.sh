#!/bin/bash
BASE_URL="http://localhost:3000"
PUMA_PIDS=$(pgrep -f puma | wc -l)

echo "🌱 LOCAL DEV TESTS - $BASE_URL (Puma $PUMA_PIDS workers)"
echo "=========================================="

test_gps() {
  echo "🛰️  Phase 8 GPS:"
  curl -fsSL -w "HTTP %{http_code}\n" -o /dev/null "$BASE_URL/api/v1/realtime" || echo "❌ GPS [FAILED]"
}

test_phase7() {
  echo "📋 Phase 7 Enterprise:"
  for endpoint in electronic_signatures dea_shipments transport_anomalies; do
    curl -fsSL -w "[%{http_code}]" -o /dev/null "$BASE_URL/$endpoint" 2>/dev/null || echo "[$endpoint] ❌"
  done
}

test_phase9() {
  echo "💳 Phase 9 Stripe Billing:"
  curl -fsSL -w "[%{http_code}]" -o /dev/null "$BASE_URL/billing" 2>/dev/null || echo "[billing] ❌"
}

test_dashboard() {
  echo "🧪 React Dashboard: $BASE_URL/dashboard (OPEN BROWSER)"
}

test_gps
test_phase7
test_phase9
test_dashboard

echo "✅ LOCAL TESTS COMPLETE - $(date)"
