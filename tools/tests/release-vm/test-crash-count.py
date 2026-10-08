#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The VM crash gate must distinguish zero crashes from an unavailable collector."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent


class CrashCountTest(unittest.TestCase):
    def run_collector(self, stdout="", stderr="", code=0, missing=False):
        with tempfile.TemporaryDirectory() as directory:
            if not missing:
                collector = Path(directory) / "coredumpctl"
                collector.write_text(f"#!{sys.executable}\nimport sys\n"
                                     f"sys.stdout.write({stdout!r})\nsys.stderr.write({stderr!r})\n"
                                     f"sys.exit({code})\n")
                collector.chmod(0o755)
            return subprocess.run([sys.executable, str(HERE / "crash-count.py")],
                                  env={**os.environ, "PATH": directory}, capture_output=True, text=True)

    def test_missing_collector_is_failure(self):
        result = self.run_collector(missing=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("coredumpctl unavailable", result.stderr)

    def test_explicit_no_coredumps_is_zero(self):
        result = self.run_collector(stderr="No coredumps found.\n", code=1)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "0\n")

    def test_json_rows_are_counted(self):
        result = self.run_collector(stdout='[{"COREDUMP_PID":1},{"COREDUMP_PID":2}]\n')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "2\n")

    def test_collector_error_is_failure(self):
        result = self.run_collector(stderr="Failed to open journal\n", code=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("coredumpctl failed", result.stderr)

    def test_malformed_output_is_failure(self):
        result = self.run_collector(stdout="not json\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("invalid coredumpctl JSON", result.stderr)

    def test_non_array_output_is_failure(self):
        result = self.run_collector(stdout='{"error":"not a list"}\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("coredumpctl JSON is not a list", result.stderr)


if __name__ == "__main__":
    unittest.main()
