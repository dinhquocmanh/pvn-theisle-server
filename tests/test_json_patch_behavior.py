#!/usr/bin/env python3
"""Regression tests for JSON integration-config updates in scripts/entry.sh."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
ENTRY_SCRIPT = PROJECT_ROOT / "scripts" / "entry.sh"


class JsonPatchBehaviorTest(unittest.TestCase):
    def setUp(self):
        self.workspace = Path(tempfile.mkdtemp())
        self.game_dir = self.workspace / "game"
        self.binary_dir = self.game_dir / "TheIsle" / "Binaries" / "Linux"
        self.binary_dir.mkdir(parents=True)
        executable = self.binary_dir / "TheIsleServer-Linux-Shipping"
        executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        executable.chmod(0o755)
        for name in ("libisleplugin.so", "TheIsleProxPlugin.so"):
            plugin = self.binary_dir / name
            plugin.write_bytes(b"placeholder")
            plugin.chmod(0o755)
        launcher = self.game_dir / "TheIsleServer.sh"
        launcher.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        launcher.chmod(0o755)
        steamcmd = self.workspace / "steamcmd"
        steamcmd.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        steamcmd.chmod(0o755)
        self.environment = {
            **os.environ,
            "GAME_DIR": str(self.game_dir),
            "STEAMCMD": str(steamcmd),
            "UPDATE_ON_START": "false",
            "UPDATE_MODS": "false",
            "ISLEPILOT_API_KEY": "test-islepilot-key",
            "ISLEVOICE_SERVER_HASH": "test-voice-hash",
            "EOS_DEDICATED_SERVER_CLIENT_ID": "test-eos-client-id",
            "EOS_DEDICATED_SERVER_CLIENT_SECRET": "test-eos-client-secret",
        }

    def tearDown(self):
        shutil.rmtree(self.workspace)

    def run_entrypoint(self):
        return subprocess.run(
            ["bash", str(ENTRY_SCRIPT)],
            cwd=PROJECT_ROOT,
            env=self.environment,
            check=False,
            text=True,
            capture_output=True,
        )

    def test_does_not_create_missing_integration_json_files(self):
        completed = self.run_entrypoint()
        self.assertEqual(completed.returncode, 0, completed.stderr + completed.stdout)
        self.assertFalse((self.binary_dir / "islepilot-config.json").exists())
        self.assertFalse((self.binary_dir / "settings.json").exists())

    def test_updates_only_target_key_in_existing_json_files(self):
        islepilot = self.binary_dir / "islepilot-config.json"
        voice = self.binary_dir / "settings.json"
        islepilot.write_text('{"apiKey":"old","preserve":{"one":1}}\n', encoding="utf-8")
        voice.write_text('{"server_hash":"old","preserve":[1,2,3]}\n', encoding="utf-8")

        completed = self.run_entrypoint()
        self.assertEqual(completed.returncode, 0, completed.stderr + completed.stdout)
        self.assertEqual(
            islepilot.read_text(encoding="utf-8"),
            '{"apiKey":"test-islepilot-key","preserve":{"one":1}}\n',
        )
        self.assertEqual(
            voice.read_text(encoding="utf-8"),
            '{"server_hash":"test-voice-hash","preserve":[1,2,3]}\n',
        )


if __name__ == "__main__":
    unittest.main()
