#!/bin/bash
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
PROD_URL="https://pharma-transport-all.onrender.com"

echo -e "${YELLOW}🔒 PHARMA TRANSPORT INFOSEC v4.0 - FULL AUDIT${NC}\n"

# 1. SENSITIVE FILES
echo -e "${BLUE}🌐 SENSITIVE FILES CHECK...${NC}"
for file in .env config/master.key package.json .git/HEAD robots.txt sitemap.xml; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PROD_URL/$file")
    [ "$HTTP_CODE" = "404" ] && echo -e "  ✅ $file = ${GREEN}404 PROTECTED${NC}" || echo -e "  ❌ $file = ${RED}$HTTP_CODE EXPOSED${NC}"
done

# 2. ENDPOINTS
echo -e "\n${BLUE}📡 ENDPOINT FUNCTIONALITY TEST...${NC}"
endpoints=("/" "/dashboard" "/pfizer" "/audit_events" "/upgrade")
for endpoint in "${endpoints[@]}"; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PROD_URL$endpoint")
    echo -e "  $endpoint: ${GREEN}${HTTP_CODE}${NC}"
done

# 3. SUMMARY
echo -e "\n🎉 ${GREEN}AUDIT COMPLETE${NC}"
echo -e "${YELLOW}Next: Check Render Logs for 500 errors${NC}"
