#!/bin/bash
trucks=20
price_per_truck=500
mrr=$((trucks * price_per_truck))
arr=$((mrr * 12))

echo "💰 PHARMA TRANSPORT REVENUE"
echo "=========================="
echo "Trucks: $trucks"
echo "Price/truck: \$$price_per_truck/mo"
echo "MRR: \$$mrr/month"
echo "ARR: \$$arr/year"
