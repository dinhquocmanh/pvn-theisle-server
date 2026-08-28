# PVN The Isle Evrima Server

Docker Compose project for The Isle Dedicated Server (Evrima). Both containers run as the host `ubuntu` account (`UID:GID` `1000:1000` by default), and all persistent game data is mounted at `./data`.

## Setup

```bash
cp .env.example .env
chmod 600 .env
```

Edit `.env` before the first start:

- set `ISLEPILOT_API_KEY`, `ISLEVOICE_SERVER_HASH`, `EOS_DEDICATED_SERVER_CLIENT_ID`, and `EOS_DEDICATED_SERVER_CLIENT_SECRET` to their real credentials;
- set `RconPassword`, server name, Discord URL, ports, and game settings;
- optionally set `DISCORD_WEBHOOK_URL` to receive `<ServerName> Started.` after every successful process launch and RAM threshold alerts; set `MAX_RAM_ALERT` (default `95`) and `RAM_MONITOR_INTERVAL_SECONDS` (default `60`) as needed.

Do not commit `.env`; it contains credentials.

Start and inspect the stack:

```bash
docker compose up -d --build
docker compose logs -f theisle backup
```

The first start downloads the Evrima branch through SteamCMD. `UPDATE_ON_START=true` checks Steam every container start. `UPDATE_MODS=true` downloads these plugins on every game start:

- `data/TheIsle/Binaries/Linux/libisleplugin.so`
- `data/TheIsle/Binaries/Linux/TheIsleProxPlugin.so`

It then updates the `apiKey` in `islepilot-config.json` and `server_hash` in `settings.json`. Plugin downloads use a temporary file and are atomically moved into place only after a successful download, so a CDN failure cannot corrupt an existing plugin. Set `PLUGIN_DOWNLOAD_TIMEOUT_SECONDS` to bound a slow CDN request. Credentials are read from `.env` and are never written to the image or this repository.

## Configuration behavior

At every game-container start, `scripts/entry.sh` replaces:

`data/TheIsle/Saved/Config/LinuxServer/Game.ini`

with the settings in `.env`, preserving the sections and repeatable `AllowedClasses=` format from `configs/DefaultGame.ini`. Set `AllowedClasses` as a comma-separated list.

Published default ports are:

- game: `7777/udp` and `7777/tcp`
- query: `7778/udp`
- RCON: `8888/tcp`
- queue: `10000/tcp`

## Backups

The `backup` container runs continuously and creates a UTC timestamped snapshot every 30 minutes at:

`backups/YYYYMMDDTHHMMSSZ/`

Each snapshot contains a recursive copy of `TheIsle/Saved/PlayerData` and all top-level `*.json` files from `TheIsle/Binaries/Linux`. Snapshots older than five calendar-age days are removed automatically. Configure its schedule in `.env`:

```env
BACKUP_INTERVAL_SECONDS=1800  # 30 minutes
BACKUP_RETENTION_DAYS=5
```

After changing either value, recreate only the backup service with `docker compose up -d --force-recreate backup`.

For an immediate one-off backup:

```bash
docker compose exec -e BACKUP_RUN_ONCE=true backup /opt/theisle/scripts/backup.sh
```

Normal operation needs no cron job because the Compose `backup` service schedules it internally.

## RAM alerts

The `ram-monitor` container checks host RAM usage every 60 seconds. When usage reaches `MAX_RAM_ALERT` percent (default `95`), it posts one Discord webhook alert and does not repeat it while usage remains above the threshold. It resets after memory usage falls below the threshold, allowing one new alert on a future breach. `DISCORD_WEBHOOK_URL` must be configured for alerts to be delivered.

## Operations

```bash
docker compose ps
docker compose logs --tail=200 theisle
docker compose restart theisle
docker compose down
```

Before changing secrets or settings, update `.env` and run `docker compose up -d`. The game start script deliberately rewrites `Game.ini`, so make persistent configuration changes in `.env`, not directly in `data`.

## Requirements

- Docker Engine with the Docker Compose v2 plugin
- Host user `ubuntu` must own this project, `data/`, `backups/`, and `runtime/`
- UDP/TCP firewall rules for the selected ports

If the directory was created by root previously, fix ownership once:

```bash
sudo chown -R ubuntu:ubuntu data backups runtime
```
