#!/usr/bin/env bash
set -euo pipefail

cd "/home/ubuntu/workspace/pvn-theisle-server"
docker compose down
sleep 20
docker compose up -d
