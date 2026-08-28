#!/usr/bin/env python3
"""Regression tests for remote-VPS startup hardening."""

import unittest
from pathlib import Path

import yaml

PROJECT_ROOT = Path(__file__).resolve().parents[1]


class RemoteStartupHardeningTest(unittest.TestCase):
    def test_compose_runs_all_long_lived_services_as_ubuntu(self):
        with (PROJECT_ROOT / "docker-compose.yml").open(encoding="utf-8") as source:
            services = yaml.safe_load(source)["services"]

        for service_name in ("theisle", "backup", "ram-monitor"):
            self.assertEqual(services[service_name]["user"], "${PUID:-1000}:${PGID:-1000}")
        self.assertNotIn("bootstrap", services)

    def test_backup_requires_writable_backup_directory_before_snapshot(self):
        script = (PROJECT_ROOT / "scripts" / "backup.sh").read_text(encoding="utf-8")
        self.assertIn('mkdir -p "$BACKUP_DIR"', script)
        self.assertIn('[[ ! -w "$BACKUP_DIR" ]]', script)
        self.assertIn('ERROR: backup directory is not writable', script)

    def test_steam_network_preflight_runs_before_steamcmd(self):
        script = (PROJECT_ROOT / "scripts" / "entry.sh").read_text(encoding="utf-8")
        self.assertIn("check_steam_network()", script)
        self.assertLess(script.index("check_steam_network"), script.index('"$STEAMCMD"'))
        self.assertIn("Steam network preflight failed", script)
        self.assertNotIn("curl --fail --silent --show-error --head", script)

    def test_missing_plugins_force_initial_download_even_when_updates_disabled(self):
        script = (PROJECT_ROOT / "scripts" / "entry.sh").read_text(encoding="utf-8")
        self.assertIn('"${UPDATE_MODS,,}" == "true" || ! -f "$BINARY_DIR/libisleplugin.so"', script)
        self.assertIn('! -f "$BINARY_DIR/TheIsleProxPlugin.so"', script)


if __name__ == "__main__":
    unittest.main()
