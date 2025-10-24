#!/bin/bash
set -e

for i in 1 2 3; do
    echo "Remove old log files for broker$i"
    rm -rf mqtt-layer/broker$i/log/*
    rm -rf mqtt-layer/broker$i/data/*
done

echo "Clean up old docker containers..."
docker compose down --volumes --remove-orphans

echo "Running docker-compose..."
docker compose -f docker-compose.emqx.yml up