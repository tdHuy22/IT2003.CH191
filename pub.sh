#!/bin/bash

set -e

# === Configuration ===
BROKER_HOST="127.0.0.1"
BROKER_PORT="8883"
CLIENT_DIR="./certs/client1"
DELAY=3  # seconds between each publish

echo "🌡️  Starting random IoT publisher..."
echo "→ Broker: $BROKER_HOST:$BROKER_PORT"
echo "→ Using certs from: $CLIENT_DIR"
echo "→ Publish interval: $DELAY seconds"
echo "----------------------------"

cd "$CLIENT_DIR"

while true; do
  # Random values within realistic sensor ranges
  TEMP=$(awk -v min=20 -v max=45 'BEGIN{srand(); printf "%.1f", min+rand()*(max-min)}')
  RAIN=$(awk -v min=0 -v max=10 'BEGIN{srand(); printf "%.2f", min+rand()*(max-min)}')
  WIND=$(awk -v min=0 -v max=60 'BEGIN{srand(); printf "%.1f", min+rand()*(max-min)}')

  # Publish temperature
  mosquitto_pub \
    -h "$BROKER_HOST" \
    -p "$BROKER_PORT" \
    -t "sensor/temp" \
    -m "$TEMP" \
    --cafile ca_client.crt \
    --cert client1.crt \
    --key client1.key \
    -q 0 >/dev/null 2>&1

  # Publish rainfall
  mosquitto_pub \
    -h "$BROKER_HOST" \
    -p "$BROKER_PORT" \
    -t "sensor/rain" \
    -m "$RAIN" \
    --cafile ca_client.crt \
    --cert client1.crt \
    --key client1.key \
    -q 0 >/dev/null 2>&1

  # Publish wind speed
  mosquitto_pub \
    -h "$BROKER_HOST" \
    -p "$BROKER_PORT" \
    -t "sensor/wind" \
    -m "$WIND" \
    --cafile ca_client.crt \
    --cert client1.crt \
    --key client1.key \
    -q 0 >/dev/null 2>&1

  # Log to console
  echo "📡 Sent → Temp: ${TEMP}°C | Rain: ${RAIN}mm/h | Wind: ${WIND}km/h"

  sleep "$DELAY"
done
