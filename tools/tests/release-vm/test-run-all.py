#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise the real campaign runner with a deterministic child VM boundary."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent


class RunAllTest(unittest.TestCase):
    def run_campaign(self, child, names=("first",), missing=()):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copy2(HERE / "run-all.sh", root / "run-all.sh")
            (root / "vmtest.sh").write_text("#!/bin/bash\nset -eu\n"
                'mkdir -p "$PF_VM_HOME/results/$1"\n' + child)
            for name in names:
                if name not in missing:
                    (root / "vms" / name).mkdir(parents=True)
            result = subprocess.run(["bash", str(root / "run-all.sh"), *(name + ":deb" for name in names)],
                env={**os.environ, "PF_VM_HOME": directory, "PF_PUBLIC": "1"}, capture_output=True, text=True)
            return result

    def test_child_failure_propagates(self):
        result = self.run_campaign('echo "FAIL: crash collector" >"$PF_VM_HOME/results/$1/steps.log"\nexit 7\n')
        self.assertEqual(result.returncode, 7)

    def test_remaining_requested_vms_are_accounted_after_failure(self):
        result = self.run_campaign('echo "done $1" >"$PF_VM_HOME/results/$1/steps.log"\n'
            '[ "$1" != first ] || exit 7\n', names=("first", "second"))
        self.assertEqual(result.returncode, 7)
        self.assertIn("done second", result.stdout)

    def test_missing_vm_is_failure(self):
        result = self.run_campaign("exit 0\n", missing=("first",))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no VM", result.stdout)

    def test_failure_marker_is_not_a_pass(self):
        result = self.run_campaign('echo "FAIL: install" >"$PF_VM_HOME/results/$1/steps.log"\nexit 0\n')
        self.assertNotEqual(result.returncode, 0)

    def test_complete_success_is_zero(self):
        result = self.run_campaign('echo "done $1" >"$PF_VM_HOME/results/$1/steps.log"\nexit 0\n')
        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
