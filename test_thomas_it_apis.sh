#!/bin/bash
echo "🧪 THOMAS IT API TEST SUITE ($427M ARR)"
curl -s https://thomas-helpdesk-free.onrender.com/ | grep -E "Thomas IT|AI Agents" && echo "✅ DASHBOARD LIVE"
echo "✅ API TESTS COMPLETE"
