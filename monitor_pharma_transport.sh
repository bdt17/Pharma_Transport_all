#!/bin/bash
echo "👀 PHARMA TRANSPORT MONITOR [$(date)]"
while true; do
  ts=$(date '+%H:%M:%S')
  size=$(curl -s --max-time 10 https://thomas-helpdesk-free.onrender.com/ | wc -c)
  status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 https://thomas-helpdesk-free.onrender.com/)
  [ "$status" = "200" ] && echo "[$ts] ✅ LIVE | ${size}b" || echo "[$ts] ❌ DOWN | HTTP:$status"
  sleep 30
done
