#!/usr/bin/env python3
"""Regression tests for remote-VPS startup hardening."""

import unittest
from pathlib import Path

import yaml

PROJECT_ROOT = Path(__file__).resolve().parents[1]


class RemoteStartupHardeningTest(unittest.TestCase):
    def test_compose_bootstraps_host_bind_mount_ownership_before_dependents(self):
        with (PROJECT_ROOT / "docker-compose.yml").open(encoding="utf-8") as source:
            services = yaml.safe_load(source)["services"]

        bootstrap = services["bootstrap"]
        self.assertEqual(bootstrap["user"], "0:0")
        self.assertIn("./backups:/backups", bootstrap["volumes"])
        self.assertIn("./runtime:/runtime", bootstrap["volumes"])
        for service_name in ("theisle", "backup", "ram-monitor"):
            self.assertEqual(
                services[service_name]["depends_on"]["bootstrap"]["condition"],
                "service_completed_successfully",
            )

    def test_backup_requires_writable_backup_directory_before_snapshot(self):
        script = (PROJECT_ROOT / "scripts" / "backup.sh").read_text(encoding="utf-8")
        self.assertIn('mkdir -p "$BACKUP_DIR"', script)
        self.assertIn('[[ -w "$BACKUP_DIR" ]]', script)
        self.assertIn('ERROR: backup directory is not writable', script)

    def test_steam_network_preflight_runs_before_steamcmd(self):
        script = (PROJECT_ROOT / "scripts" / "entry.sh").read_text(encoding="utf-8")
        self.assertIn("check_steam_network()", script)
        self.assertLess(script.index("check_steam_network"), script.index('"$STEAMCMD"'))
        self.assertIn("Steam network preflight failed", script)


if __name__ == "__main__":
    unittest.main()
