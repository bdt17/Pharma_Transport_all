#!/bin/bash
echo "=== DEBUGGING Pharma Transport Pages ==="
echo "1. DASHBOARD (/) - Expect: Leaflet map + trucks"
curl -s -H "Accept: text/html" https://pharma-transport-all.onrender.com/ | head -50
echo -e "\n=== PAGE 1 STATUS: ${?} ===\n"

echo "2. LANDING (/landing) - Expect: Pharma GEO-FENCING HTML"
curl -s -H "Accept: text/html" https://pharma-transport-all.onrender.com/landing | head -50
echo -e "\n=== PAGE 2 STATUS: ${?} ===\n"

echo "3. RAW HTML check (first 200 chars each)"
echo "DASHBOARD RAW:"
curl -s https://pharma-transport-all.onrender.com/ | head -c 200
echo ""
echo "LANDING RAW:"
curl -s https://pharma-transport-all.onrender.com/landing | head -c 200
