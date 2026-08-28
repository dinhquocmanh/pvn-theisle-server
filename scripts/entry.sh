#!/usr/bin/env bash
set -Eeuo pipefail

GAME_DIR="${GAME_DIR:-/home/ubuntu/Steam/steamapps/common/The Isle Dedicated Server}"
BINARY_DIR="$GAME_DIR/TheIsle/Binaries/Linux"
CONFIG_DIR="$GAME_DIR/TheIsle/Saved/Config/LinuxServer"
GAME_INI="$CONFIG_DIR/Game.ini"
STEAMCMD="${STEAMCMD:-/home/steam/steamcmd/steamcmd.sh}"

log() {
  printf '[%s] %s\n' "$(date -Is)" "$*"
}

require_value() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$value" || "$value" == "CHANGE_ME" ]]; then
    log "ERROR: $name must be set in .env"
    exit 1
  fi
}

install_server() {
  if [[ ! -x "$STEAMCMD" ]]; then
    log "ERROR: steamcmd not found at $STEAMCMD"
    exit 1
  fi

  if [[ ! -x "$GAME_DIR/TheIsleServer.sh" || "${UPDATE_ON_START,,}" == "true" ]]; then
    log "Installing/updating The Isle Dedicated Server branch ${STEAM_BRANCH:-evrima}"
    "$STEAMCMD" \
      +force_install_dir "$GAME_DIR" \
      +login anonymous \
      +app_update 412680 -beta "${STEAM_BRANCH:-evrima}" \
      +quit
  fi
}

write_game_ini() {
  mkdir -p "$CONFIG_DIR"
  {
    printf ';METADATA=(Diff=true, UseCommands=true)\n'
    printf '[/Script/TheIsle.TIGameSession]\n'
    local key
    for key in \
      ServerName Discord MapName MaxPlayerCount bEnableHumans bServerPassword \
      ServerPassword bServerWhitelist bEnableGlobalChat bQueueEnabled QueuePort \
      QueueJoinTimeoutSeconds QueueHeartbeatIntervalSeconds QueueHeartbeatTimeoutSeconds \
      QueueHeartbeatMaxMisses bRconEnabled RconPassword RconPort bRandomWeatherEnabled \
      MinWeatherVariationInterval MaxWeatherVariationInterval ServerDayLengthMinutes \
      ServerNightLengthMinutes bSpawnPlants PlantSpawnMultiplier bSpawnAI AISpawnInterval \
      AIDensity GrowthMultiplier bEnableDiets bEnableMutations bEnableMigration \
      MaxMigrationTime SpeciesMigrationTime bEnableMassMigration MassMigrationTime \
      MassMigrationDisableTime bEnablePatrolZones bUseRegionSpawning bUseRegionSpawnCooldown \
      RegionSpawnCooldownTimeSeconds CorpseDecayMultiplier bAllowRecordingReplay; do
      printf '%s=%s\n' "$key" "${!key:-}"
    done

    printf '\n[/Script/TheIsle.TIGameStateBase]\n'
    for key in AdminsSteamIDs WhitelistIDs VIPs; do
      printf '%s=%s\n' "$key" "${!key:-}"
    done

    local allowed_class
    IFS=',' read -ra allowed_classes <<< "${AllowedClasses:-}"
    for allowed_class in "${allowed_classes[@]}"; do
      allowed_class="${allowed_class//[[:space:]]/}"
      [[ -n "$allowed_class" ]] && printf 'AllowedClasses=%s\n' "$allowed_class"
    done
  } > "$GAME_INI"
  chmod 0600 "$GAME_INI"
  log "Wrote environment settings to $GAME_INI"
}

install_plugins() {
  require_value ISLEPILOT_API_KEY
  require_value ISLEVOICE_SERVER_HASH

  mkdir -p "$BINARY_DIR"
  download_plugin() {
    local url="$1"
    local destination="$2"
    local temporary="${destination}.download"
    rm -f "$temporary"
    curl --fail --location --retry 3 --retry-all-errors \
      --connect-timeout 20 --max-time "${PLUGIN_DOWNLOAD_TIMEOUT_SECONDS:-300}" \
      --output "$temporary" "$url"
    chmod 0755 "$temporary"
    mv -f "$temporary" "$destination"
  }

  if [[ "${UPDATE_MODS,,}" == "true" ]]; then
    log "Downloading IslePilot and Isle Voice plugins"
    download_plugin https://islepilot.eu/cdn/plugin/libisleplugin.so "$BINARY_DIR/libisleplugin.so"
    download_plugin https://cdn.isle-voip.com/server/linux/TheIsleProxPlugin.so "$BINARY_DIR/TheIsleProxPlugin.so"
  else
    log "Skipping plugin download; using files already present in $BINARY_DIR"
  fi

  if [[ -f "$BINARY_DIR/libisleplugin.so" && -f "$BINARY_DIR/TheIsleProxPlugin.so" ]]; then
    chmod 0755 "$BINARY_DIR/libisleplugin.so" "$BINARY_DIR/TheIsleProxPlugin.so"
  else
    log "WARNING: one or more plugin files are absent; game will start without a fresh plugin update"
  fi

  python3 - "$BINARY_DIR/islepilot-config.json" "$BINARY_DIR/settings.json" <<'PY'
import json
import os
import re
import sys

for path, key, value in (
    (sys.argv[1], "apiKey", os.environ["ISLEPILOT_API_KEY"]),
    (sys.argv[2], "server_hash", os.environ["ISLEVOICE_SERVER_HASH"]),
):
    if not os.path.isfile(path):
        print(f"Skipping missing integration config: {path}")
        continue
    with open(path, encoding="utf-8") as source:
        content = source.read()
    pattern = rf'("{re.escape(key)}"\s*:\s*)"(?:[^"\\]|\\.)*"'
    replacement = lambda match: match.group(1) + json.dumps(value)
    updated, replacements = re.subn(pattern, replacement, content, count=1)
    if replacements != 1:
        raise SystemExit(f"Missing string key {key!r} in existing JSON file: {path}")
    temporary_path = f"{path}.tmp"
    with open(temporary_path, "w", encoding="utf-8") as destination:
        destination.write(updated)
    os.replace(temporary_path, path)
PY
  for config_file in "$BINARY_DIR/islepilot-config.json" "$BINARY_DIR/settings.json"; do
    if [[ -f "$config_file" ]]; then
      chmod 0600 "$config_file"
    fi
  done
}

patch_server_launcher() {
  local launcher="$GAME_DIR/TheIsleServer.sh"
  local temporary="${launcher}.tmp"

  if [[ ! -x "$BINARY_DIR/TheIsleServer-Linux-Shipping" ]]; then
    log "ERROR: game executable is missing: $BINARY_DIR/TheIsleServer-Linux-Shipping"
    exit 1
  fi
  if [[ ! -f "$BINARY_DIR/libisleplugin.so" || ! -f "$BINARY_DIR/TheIsleProxPlugin.so" ]]; then
    log "ERROR: cannot patch launcher because both plugin libraries are required"
    exit 1
  fi

  cat > "$temporary" <<'SH'
#!/bin/sh

ROOT=$(dirname "$0")
cd "$ROOT/TheIsle/Binaries/Linux" || exit 1

export LD_LIBRARY_PATH="."
export LD_PRELOAD="./libisleplugin.so:./TheIsleProxPlugin.so"

exec ./TheIsleServer-Linux-Shipping TheIsle "$@"
SH
  chmod 0755 "$temporary"
  mv -f "$temporary" "$launcher"
  log "Patched $launcher to preload IslePilot and Isle Voice plugins"
}

notify_started() {
  [[ -n "${DISCORD_WEBHOOK_URL:-}" ]] || return 0
  local server_name="${ServerName:-The Isle Server}"
  local payload
  payload="$(python3 -c 'import json, sys; print(json.dumps({"content": sys.argv[1]}))' "${server_name} Started.")"
  curl --fail --silent --show-error --retry 3 --retry-all-errors \
    -H 'Content-Type: application/json' \
    --data "$payload" \
    "$DISCORD_WEBHOOK_URL" \
    && log "Sent startup webhook" \
    || log "WARNING: startup webhook failed"
}

server_pid=""
stop_server() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    log "Stopping The Isle Dedicated Server"
    kill -INT "$server_pid"
    wait "$server_pid" || true
  fi
}
trap stop_server SIGINT SIGTERM

mkdir -p "$GAME_DIR"
install_server
write_game_ini
install_plugins
patch_server_launcher
require_value EOS_DEDICATED_SERVER_CLIENT_ID
require_value EOS_DEDICATED_SERVER_CLIENT_SECRET

log "Starting The Isle Dedicated Server"
"$GAME_DIR/TheIsleServer.sh" \
  "?Port=${GAME_PORT:-7777}?QueryPort=${QUERY_PORT:-7778}" \
  -log -LOCALLOGTIMES \
  "-ini:Engine:[EpicOnlineServices]:DedicatedServerClientId=${EOS_DEDICATED_SERVER_CLIENT_ID}" \
  "-ini:Engine:[EpicOnlineServices]:DedicatedServerClientSecret=${EOS_DEDICATED_SERVER_CLIENT_SECRET}" &
server_pid="$!"
notify_started
wait "$server_pid"
