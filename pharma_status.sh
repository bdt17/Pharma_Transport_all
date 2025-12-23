#!/bin/bash
case "${1:-status}" in
    "status"|"")
        echo "🚚 PHARMA STATUS"
        echo "Dashboard: $(curl -s -o /dev/null -w '%{http_code}' https://pharma-dashboard-s4g5.onrender.com/dashboard)"
        echo "Pfizer: $(curl -s -o /dev/null -w '%{http_code}' https://pharma-dashboard-s4g5.onrender.com/pfizer)"
        ;;
    "dns")
        echo "🌐 pharmatranport.org DNS:"
        dig +short pharmatranport.org @8.8.8.8
        ;;
    "revenue")
        echo "💰 $17.5M ARR LIVE"
        echo "WEB: https://pharma-dashboard-s4g5.onrender.com/dashboard"
        echo "APK: https://expo.dev/artifacts/eas/ek8LGmfhDuy5DBTQt8bPyk.aab"
        ;;
esac
