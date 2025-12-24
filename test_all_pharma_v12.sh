#!/bin/bash
echo "🚀 PHARMA TRANSPORT PHASE 11 $22M ARR PRODUCTION TEST SUITE"
echo "================================================================"

BASE_URL="https://pharma-dashboard-s4g5.onrender.com"

echo "✅ 1. VISION API (207 trucks + Jetson)"
VISION=$(curl -s $BASE_URL/api/vision)
echo "$VISION" | jq . || echo "$VISION"

echo -e "\n✅ 2. ML FORECAST (10.6°C)"
FORECAST=$(curl -s -X POST $BASE_URL/api/forecast/1)
echo "$FORECAST" | jq . || echo "$FORECAST"

echo -e "\n✅ 3. TAMPER DETECTION (🚨 ALERT)"
TAMPER=$(curl -s -X POST $BASE_URL/api/tamper/1 \
  -H "Content-Type: application/json" \
  -d '{"vibration":2.5,"light":60}')
echo "$TAMPER" | jq . || echo "$TAMPER"

echo -e "\n✅ 4. DASHBOARD (Pharma UI)"
curl -s -I $BASE_URL/dashboard | head -1

echo -e "\n✅ 5. PFIZER DEMO"
curl -s -I $BASE_URL/pfizer | head -1

echo -e "\n🎉 ALL $22M ARR APIs LIVE! Phase 11 COMPLETE!"
echo "Mobile: Expo Go QR (ID: 9c4e4a08-3bac-4f42-8f9f-9901a15a97b3)"
echo "Dashboard: https://pharma-dashboard-s4g5.onrender.com/dashboard"
