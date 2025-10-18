#!/bin/bash

set -e

cd certs/express

echo "Subscribing to topic '+/sensor/+ and sensor/+'"

mosquitto_sub \
  -h 127.0.0.1 \
  -p 18884 \
  -t "+/sensor/+" \
  -t "sensor/+" \
  --cafile ca_org.crt \
  --cert express.crt \
  --key express.key \
  -d

