#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Safety checks for the P0 private-HOME seed, using only the Python standard library."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PREPARER = Path(__file__).with_name("prepare_seed.py")


class SeedTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="pf-layout-seed-", dir="/tmp/opencode")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.stage = self.root / "build/stage"
        self.rules = self.stage / ".local/share/kwin/scripts/plasmafusion-placement/contents/ui/Tiling.js"
        self.rules.parent.mkdir(parents=True)
        self.rules.write_text("// exact staged tiling rules\n")
        self.output = self.root / "build/seed"

    def run_seed(self):
        return subprocess.run(
            [sys.executable, str(PREPARER), "--stage", str(self.stage), "--output", str(self.output)],
            cwd=self.root, capture_output=True, text=True, timeout=10, check=False,
        )

    def test_creates_only_private_probe_packages(self):
        result = self.run_seed()
        self.assertEqual(result.returncode, 0, result.stderr)
        script = self.output / ".local/share/kwin/scripts/plasmafusion-layout-probe"
        applet = self.output / ".local/share/plasma/plasmoids/org.plasmafusion.layoutprobe"
        self.assertEqual(json.loads((script / "metadata.json").read_text())["KPlugin"]["Id"],
                         "plasmafusion-layout-probe")
        self.assertEqual((script / "contents/ui/Tiling.js").read_bytes(), self.rules.read_bytes())
        self.assertTrue((applet / "contents/config/main.xml").is_file())
        self.assertIn("plasmafusion-layout-probeEnabled=true", (self.output / ".config/kwinrc").read_text())
        self.assertFalse((self.output / ".config/plasma-org.kde.plasma.desktop-appletsrc").exists())

    def test_refuses_an_existing_seed_without_overwriting_it(self):
        self.output.mkdir()
        sentinel = self.output / "sentinel"
        sentinel.write_text("keep this evidence")
        result = self.run_seed()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already exists", result.stderr)
        self.assertEqual(sentinel.read_text(), "keep this evidence")
        self.assertEqual(list(self.output.iterdir()), [sentinel])

    def test_refuses_an_output_outside_the_private_build_directory(self):
        self.output = self.root / ".config"
        result = self.run_seed()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("under the current worktree's build directory", result.stderr)
        self.assertFalse(self.output.exists())

    def test_missing_stage_leaves_no_partial_seed(self):
        self.rules.unlink()
        result = self.run_seed()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("staged Tiling.js", result.stderr)
        self.assertFalse(self.output.exists())

    def run_check(self):
        return subprocess.run(
            [sys.executable, str(PREPARER), "--check-result", str(self.output)],
            cwd=self.root, capture_output=True, text=True, timeout=10, check=False,
        )

    def result_files(self, session_status=0):
        self.output.mkdir()
        (self.output / "scenario.log").write_text(f"scenario rc=0\nsession rc={session_status}\n")
        (self.output / "container.log").write_text("session rc=0\n")
        (self.output / "layout-probe-result.json").write_text(json.dumps({
            "schema": 1, "passed": True, "checks": ["roundtrip-native", "retirement"],
        }))

    def test_result_check_rejects_outer_zero_with_failed_scenario(self):
        self.result_files(session_status=1)
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("scenario did not finish successfully", result.stderr)

    def test_result_check_requires_explicit_receipt(self):
        self.result_files()
        (self.output / "layout-probe-result.json").unlink()
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing probe receipt", result.stderr)

    def test_result_check_rejects_incomplete_checks(self):
        self.result_files()
        (self.output / "layout-probe-result.json").write_text(json.dumps({
            "schema": 1, "passed": True, "checks": ["roundtrip-native"],
        }))
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("incomplete probe receipt", result.stderr)

    def test_result_check_accepts_a_complete_success(self):
        self.result_files()
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
