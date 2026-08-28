#!/usr/bin/env bash
set -Eeuo pipefail

GAME_DIR="${GAME_DIR:-/home/ubuntu/Steam/steamapps/common/The Isle Dedicated Server}"
PLAYER_DATA_DIR="$GAME_DIR/TheIsle/Saved/PlayerData"
BINARY_DIR="$GAME_DIR/TheIsle/Binaries/Linux"
BACKUP_DIR="${BACKUP_DIR:-/backup}"
INTERVAL_SECONDS="${BACKUP_INTERVAL_SECONDS:-1800}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-5}"

log() {
  printf '[%s] %s\n' "$(date -Is)" "$*"
}

backup_once() {
  local timestamp snapshot staging json_count
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  snapshot="$BACKUP_DIR/$timestamp"
  staging="$BACKUP_DIR/.${timestamp}.partial"

  mkdir -p "$BACKUP_DIR"
  if [[ ! -w "$BACKUP_DIR" ]]; then
    log "ERROR: backup directory is not writable: $BACKUP_DIR"
    return 1
  fi
  rm -rf "$staging"
  mkdir -p "$staging/PlayerData" "$staging/LinuxJson"

  if [[ -d "$PLAYER_DATA_DIR" ]]; then
    cp -a "$PLAYER_DATA_DIR/." "$staging/PlayerData/"
  else
    log "WARNING: PlayerData directory does not exist yet: $PLAYER_DATA_DIR"
  fi

  if [[ -d "$BINARY_DIR" ]]; then
    while IFS= read -r -d '' file; do
      cp -a "$file" "$staging/LinuxJson/"
    done < <(find "$BINARY_DIR" -maxdepth 1 -type f -name '*.json' -print0)
  else
    log "WARNING: Linux binary directory does not exist yet: $BINARY_DIR"
  fi

  json_count="$(find "$staging/LinuxJson" -maxdepth 1 -type f -name '*.json' | wc -l)"
  mv "$staging" "$snapshot"
  chmod -R u=rwX,go= "$snapshot"
  log "Created backup $snapshot (JSON files: $json_count)"

  find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name '20*' -mtime "+$RETENTION_DAYS" -print -exec rm -rf {} +
}

if [[ "${BACKUP_RUN_ONCE:-false}" == "true" ]]; then
  backup_once
  exit 0
fi

while true; do
  if ! backup_once; then
    log "ERROR: backup run failed"
  fi
  sleep "$INTERVAL_SECONDS"
done
