#!/usr/bin/env bash
set -Eeuo pipefail

INTERVAL_SECONDS="${RAM_MONITOR_INTERVAL_SECONDS:-60}"
THRESHOLD_PERCENT="${MAX_RAM_ALERT:-95}"
STATE_FILE="${RAM_ALERT_STATE_FILE:-/runtime/theisle-ram-alert.state}"
MEMINFO_PATH="${HOST_MEMINFO_PATH:-/host-proc/meminfo}"

log() {
  printf '[%s] %s\n' "$(date -Is)" "$*"
}

read_memory_usage() {
  local total available used
  total="$(awk '/^MemTotal:/ {print $2}' "$MEMINFO_PATH")"
  available="$(awk '/^MemAvailable:/ {print $2}' "$MEMINFO_PATH")"
  if [[ ! "$total" =~ ^[0-9]+$ || ! "$available" =~ ^[0-9]+$ || "$total" -eq 0 ]]; then
    return 1
  fi
  used=$((total - available))
  printf '%s %s\n' "$used" "$total"
}

send_alert() {
  local percent="$1"
  local used_bytes="$2"
  local max_bytes="$3"
  local server_name="${ServerName:-The Isle Server}"
  local content
  content="$(python3 -c 'import json, sys; print(json.dumps({"content": sys.argv[1]}))' "⚠️ ${server_name}: RAM usage is ${percent}% (${used_bytes}/${max_bytes} bytes), exceeding MAX_RAM_ALERT=${THRESHOLD_PERCENT}%.")"
  curl --fail --silent --show-error --retry 3 --retry-all-errors \
    -H 'Content-Type: application/json' \
    --data "$content" \
    "$DISCORD_WEBHOOK_URL"
}

check_once() {
  local current maximum percent alerted
  if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
    log "RAM monitor disabled: DISCORD_WEBHOOK_URL is empty"
    return 0
  fi
  if ! read -r current maximum < <(read_memory_usage); then
    log "WARNING: unable to read host memory metrics from $MEMINFO_PATH"
    return 0
  fi

  percent=$((current * 100 / maximum))
  alerted="$(cat "$STATE_FILE" 2>/dev/null || true)"
  if (( percent >= THRESHOLD_PERCENT )); then
    if [[ "$alerted" != "alerted" ]]; then
      if send_alert "$percent" "$current" "$maximum"; then
        printf 'alerted\n' > "$STATE_FILE"
        log "RAM alert sent at ${percent}%"
      else
        log "WARNING: RAM webhook delivery failed at ${percent}%"
      fi
    fi
  else
    rm -f "$STATE_FILE"
  fi
}

if [[ "${RAM_MONITOR_RUN_ONCE:-false}" == "true" ]]; then
  check_once
  exit 0
fi

while true; do
  check_once
  sleep "$INTERVAL_SECONDS"
done
