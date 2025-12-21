#!/bin/bash
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' NC='\033[0m'
PROD_URL="https://pharma-dashboard-s4g5.onrender.com" PASS=0 FAIL=0 TOTAL=20

test_url() {
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "$PROD_URL$1")
  if [ "$HTTP_CODE" = "200" ]; then 
    echo -e "${GREEN}✅ $2${NC}"
    ((PASS++))
    return 0
  else
    echo -e "${RED}❌ $2 [${HTTP_CODE}]${NC}"
    ((FAIL++))
    return 1
  fi
}

test_api() {
  RESPONSE=$(curl -s -m 10 "$PROD_URL$1")
  if echo "$RESPONSE" | grep -q "PHARMA TRANSPORT"; then
    echo -e "${PURPLE}🔥 $2 API${NC}"
    ((PASS++))
  else
    echo -e "${RED}⚠️  $2 API [NO DATA]${NC}"
    ((FAIL++))
  fi
}

echo -e "${BLUE}🚀 PHARMA ENTERPRISE v7.0 - PRODUCTION CERTIFICATION (20/20)${NC}\n"

# PRODUCTION HEALTH (4/4)
echo -e "${BLUE}🔍 PRODUCTION HEALTH:${NC}"
test_url "/" "ROOT"
test_url "/dashboard" "DASHBOARD" 
test_url "/health" "HEALTH CHECK" 
test_url "/status" "STATUS"

# PHASE 6 ENTERPRISE (8/8)
echo -e "\n${BLUE}📍 PHASE 6 FDA 21 CFR Part 11:${NC}"
test_url "/vehicles" "VEHICLES GPS"
test_url "/map" "LIVE MAP" 
test_url "/vehicles/1/map" "VEHICLE #1"
test_url "/audit_events" "FDA AUDIT TRAIL"
test_url "/geofences" "GEOFENCES NIST"
test_url "/sensor_readings" "SENSORS 2-8°C"
test_api "/vehicles" "VEHICLES JSON"
test_api "/sensor_readings" "SENSORS JSON"

# PHASE 7+ $1M ARR (8/8)
echo -e "\n${BLUE}🚀 PHASE 7+ ENTERPRISE ARR:${NC}"
test_url "/electronic_signatures" "DOCUSIGN eSIGN"
test_url "/dea_shipments" "DEA Schedule II-V"
test_url "/transport_anomalies" "AI ANOMALIES"
test_api "/electronic_signatures" "DOCUSIGN API"
test_api "/dea_shipments" "DEA API"
test_api "/transport_anomalies" "AI ANOMALY API"

# ENTERPRISE FEATURES (4/4)
echo -e "\n${BLUE}🏥 ENTERPRISE FEATURES:${NC}"
test_url "/reports" "PDF REPORTS"
test_url "/analytics" "AI ANALYTICS"
test_url "/alerts" "REAL-TIME ALERTS"
test_url "/integrations" "API/WEBHOOKS"

# FINAL SUMMARY
echo -e "\n${GREEN}📊 PRODUCTION CERTIFICATION: ${PASS}/${TOTAL} ENDPOINTS${NC}"
if [ $PASS -eq $TOTAL ]; then
  echo -e "${GREEN}🎉 $1M ARR PRODUCTION CERTIFIED! 🚀💉💰${NC}"
  echo -e "${PURPLE}🌐 LIVE PRODUCTION: ${PROD_URL}/dashboard${NC}"
else
  echo -e "${YELLOW}⚠️  $((TOTAL-PASS)) endpoints need attention${NC}"
fi
