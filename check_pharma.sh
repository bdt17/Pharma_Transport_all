#!/bin/bash
case "${1:-status}" in
    "status"|"")
        echo "🚚 PHARMA STATUS - 200 OK"
        curl -s -w "Dashboard: %{http_code} | Pfizer: %{http_code}\n" \
        -o /dev/null https://pharma-dashboard-s4g5.onrender.com/dashboard \
        https://pharma-dashboard-s4g5.onrender.com/pfizer
        ;;
    "dns")
        echo "🌐 pharmatranport.org:"
        dig +short pharmatranport.org @8.8.8.8 @1.1.1.1
        ;;
    "revenue")
        echo "💰 ENTERPRISE LIVE"
        echo "WEB: https://pharma-dashboard-s4g5.onrender.com/dashboard"
        echo "APK: https://expo.dev/artifacts/eas/ek8LGmfhDuy5DBTQt8bPyk.aab"
        echo "GITHUB: https://github.com/bdt17/Pharma_Transport_all"
        ;;
esac
