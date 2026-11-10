# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import run as runner


class SessionStatusTests(unittest.TestCase):
    def test_complete_success(self):
        runner.check_session_logs("scenario rc=0\nsession rc=0\n", "session rc=0\n")

    def test_actual_session_failure(self):
        with self.assertRaises(AssertionError):
            runner.check_session_logs("scenario rc=0\nsession rc=137\n", "session rc=0\n")

    def test_missing_actual_session_status(self):
        with self.assertRaises(AssertionError):
            runner.check_session_logs("scenario rc=0\n", "session rc=0\n")

    def test_duplicate_actual_session_status(self):
        for extra in ("session rc=0\n", "session rc=137\n", "session rc=invalid\n"):
            with self.subTest(extra=extra), self.assertRaises(AssertionError):
                runner.check_session_logs("scenario rc=0\nsession rc=0\n" + extra, "session rc=0\n")

    def test_malformed_or_embedded_success_is_not_status(self):
        for status in ("session rc=01", "quoted session rc=0", "session rc=0 extra"):
            with self.subTest(status=status), self.assertRaises(AssertionError):
                runner.check_session_logs("scenario rc=0\n" + status + "\n", "session rc=0\n")

    def test_duplicate_or_failed_scenario_status(self):
        for scenario in ("scenario rc=0\nscenario rc=1\n", "scenario rc=0\nscenario rc=0\n", "scenario rc=01\n"):
            with self.subTest(scenario=scenario), self.assertRaises(AssertionError):
                runner.check_session_logs(scenario + "session rc=0\n", "session rc=0\n")

    def test_duplicate_container_status(self):
        with self.assertRaises(AssertionError):
            runner.check_session_logs("scenario rc=0\nsession rc=0\n", "session rc=1\nsession rc=0\n")


class SessionEnvironmentTests(unittest.TestCase):
    def test_rejects_seed_bypasses(self):
        for key in ("PFV_HOME_DIR", "PFV_PRE"):
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, key):
                runner.fresh_session_environment({key: "unsafe override"})

    def test_empty_seed_overrides_are_removed(self):
        inherited = {"PFV_HOME_DIR": "", "PFV_PRE": "", "PATH": "/usr/bin"}
        self.assertEqual(runner.fresh_session_environment(inherited), {"PATH": "/usr/bin"})
        self.assertIn("PFV_HOME_DIR", inherited)

    def test_main_rejects_before_runtime_or_seed_work(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "runtime.json"
            manifest.write_text(json.dumps({"image": "0" * 64, "files": {
                "kwin_wayland": "0" * 64, "libkwin.so.6.8.2": "1" * 64}}))
            args = ["run.py", str(root / "stage"), str(root / "build"), str(root / "output"),
                    "test-case", "test-image", "--runtime-manifest", str(manifest)]
            for key in ("PFV_HOME_DIR", "PFV_PRE"):
                with (self.subTest(key=key), patch.object(runner.sys, "argv", args),
                      patch.dict(runner.os.environ, {key: "unsafe override"}, clear=True),
                      patch.object(runner.subprocess, "check_output", side_effect=AssertionError("runtime inspected")) as inspect,
                      patch.object(runner.subprocess, "run", side_effect=AssertionError("runtime started")) as start):
                    with self.assertRaisesRegex(ValueError, key):
                        runner.main()
                    inspect.assert_not_called()
                    start.assert_not_called()
                    self.assertFalse((root / "output").exists())


if __name__ == "__main__":
    unittest.main()
