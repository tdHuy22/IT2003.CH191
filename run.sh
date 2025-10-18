#!/bin/bash
set -e

for i in 1 2 3; do
    echo "Remove old log files for broker$i"
    rm -f mqtt-layer/broker$i/log/*.log
done

echo "Clean up old docker containers..."
docker-compose down --volumes --remove-orphans

echo "Running docker-compose..."
docker-compose up --build