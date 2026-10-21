#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""A failing real vmtest entrypoint must release its mocked VM resource and preserve evidence; the
copy-text check, the status before it and the KDE bug 524392 workaround (its own commands, against a
stand-in systemctl) gate the run."""
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
      *kde-baloo.service*) HOME=$PF_VM_HOME/vmhome PATH=$PF_VM_HOME/vmbin:$PATH bash -c "$*" ;;
      *org.plasmafusion.CopyTextOverlay*) echo check >>"$PF_VM_HOME/copytext"; [ "$FAULT" != copytext ] && echo "overlay shown on kwin 6.8.0: shown in 50 ms" ;;
      *'plasma-fusion status'*)
        n=$(cat "$PF_VM_HOME/status" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" >"$PF_VM_HOME/status"
        [ "$FAULT" = status ] && [ "$n" = 2 ] && exit 1
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
# systemctl in the VM, for the workaround's own commands: the user manager unreachable (baloo-bus),
# no Baloo (baloo-absent), its unit masked (baloo-masked), daemon-reload failing (baloo-reload).
SYSTEMCTL = r'''#!/bin/sh
echo "$*" >>"$PF_VM_HOME/systemctl"
[ "$FAULT" != baloo-bus ] || { echo "Failed to connect to user scope bus" >&2; exit 1; }
case "$*" in
  *show*) case "$FAULT" in baloo-absent) echo not-found ;; baloo-masked) echo masked ;; *) echo loaded ;; esac ;;
  *daemon-reload*) [ "$FAULT" != baloo-reload ] ;;
esac
'''
DROPIN = "vmhome/.config/systemd/user/kde-baloo.service.d/kde-bug-524392.conf"


class VMCleanupTest(unittest.TestCase):
    def run_vm(self, fault):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            root = home / "repo/tools/tests/release-vm"
            root.mkdir(parents=True)
            (home / "repo/VERSION").write_text("0.3.1\n")
            for filename in ["vmtest.sh", "lane-env.sh", "crash-count.py", "check-copytext.sh"]:
                shutil.copy2(HERE / filename, root / filename)
            (root / "vm.sh").write_text(BOUNDARY)
            (home / "vms/test").mkdir(parents=True)
            (root / "bin").mkdir()
            sleep = root / "bin/sleep"
            sleep.write_text("#!/bin/sh\nexit 0\n")
            sleep.chmod(0o755)
            (home / "vmhome").mkdir()
            (home / "vmbin").mkdir()
            (home / "vmbin/systemctl").write_text(SYSTEMCTL)
            (home / "vmbin/systemctl").chmod(0o755)
            lane = "aur" if fault == "prerequisites" else "copr"
            result = subprocess.run(["bash", str(root / "vmtest.sh"), "test", lane], capture_output=True, text=True,
                env={**os.environ, "PF_VM_HOME": directory, "PF_PUBLIC": "0" if lane == "aur" else "1", "FAULT": fault,
                     "PF_AFTER_LOGIN": "FAULT_HOOK" if fault == "hook" else "",
                     "PATH": str(root / "bin") + ":" + os.environ["PATH"]})
            calls = (home / "calls").read_text().splitlines()
            self.checked = (home / "copytext").exists()
            self.dropin = (home / DROPIN).read_text() if (home / DROPIN).exists() else None
            self.systemctl = (home / "systemctl").read_text().splitlines() if (home / "systemctl").exists() else []
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

    def test_failed_status_after_login_is_rejected(self):
        result, calls, locked, preserved = self.run_vm("status")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL: plasma-fusion status after the login (rc=1)", result.stdout)
        self.assertNotIn("(skipped)", result.stdout)
        self.assertFalse(self.checked)
        self.assertFalse(locked)
        self.assertEqual(len(preserved), 1)

    def test_workaround_applied(self):
        result, calls, locked, preserved = self.run_vm("none")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("test system: KDE bug 524392 workaround applied (kde-baloo.service)", result.stdout)
        self.assertEqual(self.dropin, "[Service]\nEnvironment=QT_QPA_PLATFORM=offscreen\n")
        self.assertEqual(self.systemctl, ["--user show -p LoadState --value kde-baloo.service",
                                          "--user daemon-reload", "--user try-restart kde-baloo.service"])

    def test_workaround_not_needed_without_baloo(self):
        result, calls, locked, preserved = self.run_vm("baloo-absent")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("test system: KDE bug 524392 workaround not needed (no kde-baloo.service)", result.stdout)
        self.assertIsNone(self.dropin)

    def test_workaround_failures_are_rejected(self):
        for fault in ["baloo-bus", "baloo-masked", "baloo-reload"]:
            with self.subTest(fault=fault):
                result, calls, locked, preserved = self.run_vm(fault)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("FAIL: the KDE bug 524392 workaround could not be applied (rc=1)", result.stdout)
                self.assertNotIn("installer:", result.stdout)
                self.assertFalse(locked)
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
