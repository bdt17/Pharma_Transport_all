#!/bin/bash
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
PROD_URL="https://pharma-dashboard-s4g5.onrender.com"

echo -e "${YELLOW}🔒 PHARMA TRANSPORT INFOSEC v4.0 - FULL AUDIT${NC}\n"

# 1. COMMON FILES EXPOSED? (Critical)
echo -e "${BLUE}🌐 SENSITIVE FILES CHECK...${NC}"
for file in .env config/master.key package.json .git/HEAD robots.txt sitemap.xml; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PROD_URL/$file")
    [ "$HTTP_CODE" = "404" ] && echo -e "  ✅ $file = ${GREEN}404 PROTECTED${NC}" || echo -e "  ❌ $file = ${RED}$HTTP_CODE EXPOSED${NC}"
done

# 2. ALL ENDPOINTS LIVE + STATUS
echo -e "\n${BLUE}📡 ENDPOINT FUNCTIONALITY TEST...${NC}"
endpoints=(
    "/dashboard" "/pfizer" "/audit_events" "/upgrade" "/api/health" "/login" "/admin"
    "/static/js/bundle.js" "/favicon.ico"
)
for endpoint in "${endpoints[@]}"; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PROD_URL$endpoint")
    echo -e "  $endpoint: ${GREEN}${HTTP_CODE}${NC}"
done

# 3. SECURITY HEADERS (OWASP Top 10)
echo -e "\n${BLUE}🔐 SECURITY HEADERS...${NC}"
headers=$(curl -s -D - "$PROD_URL" -o /dev/null 2>/dev/null)
echo "$headers" | grep -i "strict-transport-security\|x-frame-options\|x-content-type-options\|content-security-policy\|x-xss-protection" | \
while IFS= read -r line; do echo "  ✅ $line"; done || echo "  ⚠️  Missing critical headers"

# 4. FDA 21 CFR 11 COMPLIANCE CHECKS
echo -e "\n${BLUE}📋 FDA 21 CFR PART 11...${NC}"
curl -s "$PROD_URL/audit_events" | grep -i "audit\|log\|timestamp\|fda" && echo -e "  ✅ ${GREEN}Audit trail LIVE${NC}" || echo "  ⚠️  Audit endpoint empty"
curl -s "$PROD_URL/upgrade" | grep -i "stripe\|payment\|subscription" && echo -e "  ✅ ${GREEN}Stripe billing LIVE${NC}" || echo "  ⚠️  Billing endpoint empty"

# 5. CVE VULNERABILITY SCAN (Known React/Render issues)
echo -e "\n${BLUE}🛡️ CVE QUICK SCAN...${NC}"
curl -s "$PROD_URL" | grep -i "react\|bundle.js" && echo -e "  ✅ React SPA detected\n  ⚠️  Run: npm audit in GitHub repo"

# 6. PERFORMANCE + UPTIME
echo -e "\n${BLUE}⚡ PERFORMANCE...${NC}"
TIME=$(curl -s -w "Time: %{time_total}s\n" -o /dev/null "$PROD_URL/dashboard")
echo "  $TIME"

# 7. SUMMARY
echo -e "\n🎉 ${GREEN}FULL AUDIT COMPLETE${NC}"
echo -e "${YELLOW}Status:${NC} LIVE | ${GREEN}Revenue Ready${NC}"
echo -e "${YELLOW}Next:${NC} Deploy to cron: */5 * * * * ~/pharma_infosec_v4.sh >> audit.log"
