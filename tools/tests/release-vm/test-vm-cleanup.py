#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""A failing real vmtest entrypoint must release its mocked VM resource and preserve evidence; the
copy-text check and the KDE bug 524392 workaround gate the run."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
BOUNDARY = r'''#!/bin/bash
set -eu
cmd=$1; name=$2; shift 2
echo "$cmd" >>"$PF_VM_HOME/calls"
case "$cmd" in
  start) printf overlay >"$PF_VM_HOME/vms/$name/run.qcow2" ;;
  wait) [ "$FAULT" != wait ] ;;
  stop|shot) exit 0 ;;
  ssh)
    case "$*" in
      *FAULT_HOOK*) exit 9 ;;
      *kde-baloo.service*) if [ "$FAULT" = workaround ]; then echo failed; else echo "applied (kde-baloo.service)"; fi ;;
      *org.plasmafusion.CopyTextOverlay*) echo check >>"$PF_VM_HOME/copytext"; [ "$FAULT" != copytext ] && echo "overlay shown on kwin 6.8.0: shown in 50 ms" ;;
      *'plasma-fusion status'*)
        case "$FAULT" in copytext | copytext-pass) printf 'Plasma Fusion 0.6.0\n  copytext: installed, built against kf=6.31.0\n' ;; esac ;;
      *'sh ~/install.sh --yes'*) [ "$FAULT" != install ] ;;
      *'sh ~/install.sh --dry-run'*) [ "$FAULT" != dry ] ;;
      *'sh ~/install.sh uninstall --yes'*) [ "$FAULT" != uninstall ] ;;
      *'curl -fsS -O http://10.0.2.2:8088/arch/PKGBUILD'*) [ "$FAULT" != prerequisites ] ;;
      *tty1_session*) n=$(cat "$PF_VM_HOME/session" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" >"$PF_VM_HOME/session"; echo "$n" ;;
      'python3 -')
        n=$(cat "$PF_VM_HOME/counts" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" >"$PF_VM_HOME/counts"
        if { [ "$FAULT" = first ] && [ "$n" = 1 ]; } || { [ "$FAULT" = final ] && [ "$n" = 2 ]; }; then exit 9; fi
        echo 0 ;;
    esac ;;
esac
'''


class VMCleanupTest(unittest.TestCase):
    def run_vm(self, fault):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            root = home / "repo/tools/tests/release-vm"
            root.mkdir(parents=True)
            (home / "repo/VERSION").write_text("0.3.1\n")
            for filename in ["vmtest.sh", "crash-count.py", "check-copytext.sh"]:
                shutil.copy2(HERE / filename, root / filename)
            (root / "vm.sh").write_text(BOUNDARY)
            (home / "vms/test").mkdir(parents=True)
            (root / "bin").mkdir()
            sleep = root / "bin/sleep"
            sleep.write_text("#!/bin/sh\nexit 0\n")
            sleep.chmod(0o755)
            lane = "aur" if fault == "prerequisites" else "copr"
            result = subprocess.run(["bash", str(root / "vmtest.sh"), "test", lane], capture_output=True, text=True,
                env={**os.environ, "PF_VM_HOME": directory, "PF_PUBLIC": "0" if lane == "aur" else "1", "FAULT": fault,
                     "PF_AFTER_LOGIN": "FAULT_HOOK" if fault == "hook" else "",
                     "PATH": str(root / "bin") + ":" + os.environ["PATH"]})
            calls = (home / "calls").read_text().splitlines()
            self.checked = (home / "copytext").exists()
            return result, calls, (home / "vms/test/run.qcow2").exists(), list((home / "vms/test").glob("failed-run-*.qcow2"))

    def test_initial_crash_gate_releases_vm(self):
        result, calls, locked, preserved = self.run_vm("first")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stop", calls)
        self.assertFalse(locked)
        self.assertEqual(len(preserved), 1)

    def test_final_crash_gate_releases_vm(self):
        result, calls, locked, preserved = self.run_vm("final")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stop", calls)
        self.assertFalse(locked)
        self.assertEqual(len(preserved), 1)

    def test_wait_failure_releases_started_vm(self):
        result, calls, locked, preserved = self.run_vm("wait")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stop", calls)
        self.assertFalse(locked)
        self.assertEqual(len(preserved), 1)

    def test_success_releases_vm_and_removes_overlay(self):
        result, calls, locked, preserved = self.run_vm("none")
        self.assertEqual(result.returncode, 0)
        self.assertIn("stop", calls)
        self.assertFalse(locked)
        self.assertFalse(preserved)

    def test_after_login_failure_is_rejected_and_preserved(self):
        result, calls, locked, preserved = self.run_vm("hook")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stop", calls)
        self.assertFalse(locked)
        self.assertEqual(len(preserved), 1)

    def test_copytext_failure_is_rejected_and_preserved(self):
        result, calls, locked, preserved = self.run_vm("copytext")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.checked)
        self.assertIn("FAIL: copy text's selection", result.stdout)
        self.assertIn("stop", calls)
        self.assertFalse(locked)
        self.assertEqual(len(preserved), 1)
        self.assertNotIn("installer: uninstall", result.stdout)

    def test_copytext_pass(self):
        result, calls, locked, preserved = self.run_vm("copytext-pass")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue(self.checked)
        self.assertIn("copy text's selection rc=0: overlay shown on kwin 6.8.0: shown in 50 ms", result.stdout)
        self.assertFalse(preserved)

    def test_copytext_skipped_without_the_part(self):
        result, calls, locked, preserved = self.run_vm("none")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.checked)
        self.assertIn("copy text's selection: plasma-fusion-copytext not installed (skipped)", result.stdout)

    def test_workaround_applied_and_its_failure_rejected(self):
        result, calls, locked, preserved = self.run_vm("none")
        self.assertIn("test system: KDE bug 524392 workaround applied (kde-baloo.service)", result.stdout)
        result, calls, locked, preserved = self.run_vm("workaround")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL: the KDE bug 524392 workaround could not be applied", result.stdout)
        self.assertEqual(len(preserved), 1)

    def test_installer_stage_failures_are_rejected_and_preserved(self):
        for stage in ["prerequisites", "dry", "install", "uninstall"]:
            with self.subTest(stage=stage):
                result, calls, locked, preserved = self.run_vm(stage)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("stop", calls)
                self.assertFalse(locked)
                self.assertEqual(len(preserved), 1)
                self.assertNotIn("done test", result.stdout)


if __name__ == "__main__":
    unittest.main()
