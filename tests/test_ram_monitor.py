#!/usr/bin/env python3
"""Regression tests for scripts/ram-monitor.sh."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
MONITOR = PROJECT_ROOT / "scripts" / "ram-monitor.sh"


class RamMonitorTest(unittest.TestCase):
    def setUp(self):
        self.workspace = Path(tempfile.mkdtemp())
        self.meminfo = self.workspace / "meminfo"
        self.state_file = self.workspace / "state"
        self.curl_log = self.workspace / "curl.log"
        self.bin_dir = self.workspace / "bin"
        self.bin_dir.mkdir()
        fake_curl = self.bin_dir / "curl"
        fake_curl.write_text(
            "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$CURL_LOG\"\n",
            encoding="utf-8",
        )
        fake_curl.chmod(0o755)
        self.environment = {
            **os.environ,
            "PATH": f"{self.bin_dir}:{os.environ['PATH']}",
            "CURL_LOG": str(self.curl_log),
            "HOST_MEMINFO_PATH": str(self.meminfo),
            "RAM_ALERT_STATE_FILE": str(self.state_file),
            "RAM_MONITOR_RUN_ONCE": "true",
            "RAM_MONITOR_INTERVAL_SECONDS": "1",
            "MAX_RAM_ALERT": "95",
            "DISCORD_WEBHOOK_URL": "https://example.invalid/webhook",
            "ServerName": "Test Server",
        }

    def tearDown(self):
        shutil.rmtree(self.workspace)

    def run_monitor(self, available_kib, total_kib=100):
        self.meminfo.write_text(
            f"MemTotal:       {total_kib} kB\nMemAvailable:   {available_kib} kB\n",
            encoding="utf-8",
        )
        return subprocess.run(
            ["bash", str(MONITOR)],
            cwd=PROJECT_ROOT,
            env=self.environment,
            check=False,
            text=True,
            capture_output=True,
        )

    def test_sends_one_alert_only_when_host_usage_reaches_threshold(self):
        completed = self.run_monitor(5)
        self.assertEqual(completed.returncode, 0, completed.stderr + completed.stdout)
        self.assertIn("RAM alert sent", completed.stdout)
        self.assertEqual(len(self.curl_log.read_text(encoding="utf-8").splitlines()), 1)

        completed = self.run_monitor(4)
        self.assertEqual(completed.returncode, 0, completed.stderr + completed.stdout)
        self.assertEqual(len(self.curl_log.read_text(encoding="utf-8").splitlines()), 1)

    def test_sends_new_alert_after_host_usage_recovers_then_breaches_again(self):
        self.run_monitor(5)
        self.run_monitor(20)
        completed = self.run_monitor(5)
        self.assertEqual(completed.returncode, 0, completed.stderr + completed.stdout)
        self.assertEqual(len(self.curl_log.read_text(encoding="utf-8").splitlines()), 2)


if __name__ == "__main__":
    unittest.main()
