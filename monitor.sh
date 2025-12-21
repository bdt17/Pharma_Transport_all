#!/bin/bash
while true; do
  curl -s https://pharma-dashboard-s4g5.onrender.com/health || echo "❌ DOWN $(date)"
  sleep 300
done
