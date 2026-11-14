#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""fulltest.sh against a stand-in VM: the full profile's lane passes on a system that behaves as
the installer promises (fresh and switch), and a system that does not fails the run, stops the VM
and keeps the overlay. The faults, one test each: a dry run that changes something; a set that is
half the fork, not locked, not the metapackage's build, or whose restore record is wrong; a
repository that is there and switched off; a set that holds without the lock; a lock list that
cannot be read; a status that does not see the fork or carries a note; no new session after the
logout, or no desktop after it; an idle navigation effect; a journal that cannot be read; a
switcher that does not switch, or lands on no test window; a tiler without a session; a restore
whose plan names another KWin, that leaves the fork or the repository, or takes the packages; a
status that takes the session after the restore for a fork installed by hand; a fallback that is
not one; a crash; an uninstall that leaves the lock or a package, or the theme; a VM that does
not come up. Not every check of the lane has a fault: its plumbing (the stamp, the copies into
the VM, a collector that cannot count) and the plan's wording are covered by the passing runs
only."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
# The VM: what is installed (stock, six, full, restored, gone) and which KWin the session runs
# (the installed one from the next login on), in files below $PF_VM_HOME.
BOUNDARY = r'''#!/bin/bash
set -eu
cmd=$1; name=$2; shift 2
S=$PF_VM_HOME/state
get() { cat "$S/$1" 2>/dev/null || echo "$2"; }
put() { mkdir -p "$S"; echo "$2" >"$S/$1"; }
bump() { local n; n=$(($(get "$1" 0) + 1)); put "$1" "$n"; echo "$n"; }
echo "$cmd" >>"$PF_VM_HOME/calls"
STOCK=6.8.2-3.fc44 PIN=6.8.2-3.fc44.pf3 META=0.8.0-1.fc44 RELEASED=0.7.0-1.fc44
SIX="plasma-fusion plasma-fusion-decoration plasma-fusion-settings plasma-fusion-navigation plasma-fusion-quicklook plasma-fusion-copytext"
facts() {
  local installed p kwin=$STOCK six=none full=no
  installed=$(get installed stock)
  case $installed in
    six) six=$RELEASED ;;
    full) kwin=$PIN six=$META full=yes ;;
    restored) six=$META ;;
  esac
  [ "$FAULT" = restore-keeps-fork ] && [ "$installed" = restored ] && kwin=$PIN
  [ "$FAULT" = restore-takes-six ] && [ "$installed" = restored ] && six=none
  [ "$FAULT" = six-old ] && [ "$installed" = full ] && six=$RELEASED
  for p in kwin kwin-common kwin-libs; do
    if [ "$FAULT" = half-fork ] && [ "$p" = kwin-common ]; then echo "pkg $p $STOCK"; else echo "pkg $p $kwin"; fi
  done
  if [ "$full" = yes ]; then echo "pkg plasma-fusion-full $META"; else echo "pkg plasma-fusion-full none"; fi
  for p in $SIX; do
    if [ "$FAULT" = uninstall-keeps-package ] && [ "$installed" = gone ] && [ "$p" = plasma-fusion-settings ]; then
      echo "pkg $p $META"
    else
      echo "pkg $p $six"
    fi
  done
  if [ "$FAULT" = locklist-failed ] && [ "$installed" = restored ]; then echo "locklist failed"; else echo "locklist ok"; fi
  if [ "$full" = yes ]; then
    for p in kwin kwin-common kwin-libs; do
      [ "$FAULT" = no-lock ] && [ "$p" = kwin-libs ] || echo "lock $p $PIN"
    done
    for p in kwin kwin-common kwin-libs; do
      if [ "$FAULT" = record-wrong ] && [ "$p" = kwin ]; then echo "record $p 6.8.1-1.fc44"; else echo "record $p $STOCK"; fi
    done
    echo "pin $PIN"; echo "tag v6.8.2-pf3"; echo "recordfile yes"
    if [ "$FAULT" = repo-disabled ]; then echo "repo disabled"; else echo "repo enabled"; fi
  else
    [ "$FAULT" = uninstall-leaves-lock ] && [ "$installed" = gone ] && echo "lock kwin $PIN"
    echo "recordfile no"
    if [ "$FAULT" = restore-leaves-repo ] && [ "$installed" = restored ]; then echo "repo disabled"; else echo "repo no"; fi
  fi
}
status() {
  local installed running
  installed=$(get installed stock) running=$(get running stock)
  echo "Plasma Fusion 0.8.0 (/usr/share/plasma-fusion)"
  if [ "$installed" = full ]; then
    echo "  profile: full (the maintained KWin fork, pinned at $PIN, fork tag v6.8.2-pf3)"
  else
    echo "  profile: stock (the distribution's KWin)"
  fi
  if [ "$running" = fork ] && [ "$FAULT" != status-blind ]; then
    echo "  the running KWin's capabilities:"
    echo "    thumbnail source lifecycle: version 1"
    echo "    offscreen opacity: version 1"
    echo "    transient tiling (dynamic tiling): yes"
    if [ "$installed" != full ] && [ "$FAULT" = status-by-hand ]; then
      echo "  note: this KWin advertises the fork's capabilities without the full profile (a fork installed by hand)"
    elif [ "$installed" != full ]; then
      echo "  note: the full profile is not installed and the running KWin still advertises the fork's capabilities:"
      echo "        log out and in (the KWin on the disk was put there after this session's KWin started, as after --full-restore)"
    fi
    [ "$FAULT" != status-note ] || [ "$installed" != full ] || echo "  note: run 'plasma-fusion update' to apply this version's settings"
  else
    echo "  the running KWin's capabilities: none of the fork's (every feature uses its stock fallback)"
    if [ "$installed" = full ]; then
      echo "  note: the full profile is installed and the running KWin advertises none of its capabilities:"
      echo "        log out and in (the session still runs the KWin from before the profile)"
    fi
  fi
  echo "  switched off: nothing"
}
case "$cmd" in
  start) printf overlay >"$PF_VM_HOME/vms/$name/run.qcow2" ;;
  wait) [ "$FAULT" != wait ] ;;
  stop|shot) exit 0 ;;
  ssh)
    case "$*" in
      *'full-guest.sh facts'*) facts ;;
      *'full-guest.sh kwinlog'*)
        [ "$FAULT" != kwinlog-fails ] || { echo "no kwin_wayland" >&2; exit 1; }
        if [ "$(get running stock)" = fork ]; then
          [ "$FAULT" != nav-idle ] || echo "plasmafusion-navigation: compositor lacks offscreen opacity capability version 1; the effect stays idle"
          [ "$FAULT" = nav-idle ] || printf 'plasmafusion-navigation: gesture lock on\nplasmafusion-navigation: gesture lock off\n'
        else
          [ "$FAULT" = stock-nav-runs ] || echo "plasmafusion-navigation: compositor lacks offscreen opacity capability version 1; the effect stays idle"
          [ "$FAULT" != stock-nav-runs ] || echo "plasmafusion-navigation: gesture lock on"
        fi ;;
      *'full-guest.sh active'*)
        n=$(bump active)
        if [ "$FAULT" = switcher ] || [ $((n % 2)) = 1 ]; then
          echo org.kde.kwrite
        elif [ "$FAULT" = switcher-elsewhere ]; then
          echo org.kde.plasmashell
        else
          echo org.kde.dolphin
        fi ;;
      *'full-guest.sh '*) exit 0 ;;
      *"plasmafusion-placement: tiling"*)
        if [ "$(get running stock)" = fork ]; then
          [ "$FAULT" = tiler ] || echo "plasmafusion-placement: tiling: on (2 stack window(s))"
          echo "plasmafusion-placement: tiling: off"
        else
          echo "plasmafusion-placement: tiling: the native facade is not available; the tiler needs the fork"
        fi ;;
      *'plasma-fusion status'*) status ;;
      *'install.sh --full --dry-run'*)
        [ "$FAULT" != dry-changes ] || put installed full
        echo "  sudo tee /var/lib/plasma-fusion/full-restore.txt   (records the stock KWin for --full-restore)"
        echo "  sudo dnf -y copr enable archledger/plasma-fusion-full fedora-44-x86_64"
        echo "  sudo dnf -y install plasma-fusion-full   (the six packages + the pinned KWin; replaces the stock KWin)"
        echo "  sudo dnf -y versionlock add kwin kwin-common kwin-libs   (the pin)"
        echo "  note: the fork takes KWin security fixes on its weekly cadence, which can lag Fedora by days." ;;
      *'install.sh --full --yes'*) put installed full ;;
      *'install.sh --full-restore --dry-run'*)
        r=$STOCK
        [ "$FAULT" != plan-other-kwin ] || r=$PIN
        echo "  sudo dnf -y distro-sync kwin kwin-common kwin-libs   (back to the stock KWin (recorded: kwin=$r,kwin-common=$r,kwin-libs=$r))" ;;
      *'install.sh --full-restore --yes'*) put installed restored ;;
      *'install.sh uninstall --yes'*) put installed gone ;;
      *'install-stock.sh --yes'*) put installed six ;;
      *'org.kde.Shutdown logout'*)
        case $(get installed stock) in full) put running fork ;; *) put running stock ;; esac ;;
      *tty1_session*)
        if [ "$FAULT" = no-session ]; then echo 1; else bump session; fi ;;
      *'pgrep -u pf -x kwin_wayland >/dev/null'*)
        [ "$FAULT" != no-desktop ] || [ "$(get installed stock)" != gone ] ;;
      *'distro-sync'*)
        if [ "$FAULT" = lock-loose ]; then
          echo "Downgrading: kwin"; echo "Operation aborted by the user."
        elif [ "$FAULT" = held-without-lock ]; then
          echo "Problem: cannot install both kwin-$STOCK.x86_64 from updates and kwin-$PIN.x86_64 from @System"
          echo "Skipping packages with conflicts:"; echo "Nothing to do."
        else
          echo "Nothing to do."
        fi ;;
      'python3 -')
        n=$(bump counts)
        if [ "$FAULT" = crash ] && [ "$n" = 1 ]; then echo 1; else echo 0; fi ;;
      *LookAndFeelPackage*)
        case $(get installed stock) in
          six | full | restored) echo "LookAndFeelPackage=org.plasmafusion.dark.desktop" ;;
          gone)
            if [ "$FAULT" = theme-kept ]; then
              echo "LookAndFeelPackage=org.plasmafusion.dark.desktop"
            else
              echo "LookAndFeelPackage=org.kde.breeze.desktop"
            fi ;;
          *) echo "LookAndFeelPackage=org.kde.breeze.desktop" ;;
        esac ;;
      *'date +%s'*) echo 100 ;;
      *'grep -m 1 "^PF_VERSION="'*) echo "PF_VERSION='0.7.0'" ;;
      *) exit 0 ;;
    esac ;;
esac
'''
STAMP = r'''#!/bin/sh
for out in "$@"; do :; done
printf "PF_VERSION='0.8.0'\nPF_FULL_FEDORA='44'\n" >"$out"
'''
KEYS = r'''#!/usr/bin/env python3
import sys
for step in sys.argv[2:]:
    if step.startswith("shot:"):
        open(step[5:], "w").write("png")
'''


class FullLaneTest(unittest.TestCase):
    def run_lane(self, fault, mode="fresh"):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            root = home / "repo/tools/tests/release-vm"
            root.mkdir(parents=True)
            for filename in ["fulltest.sh", "full-guest.sh", "lane-env.sh", "crash-count.py"]:
                shutil.copy2(HERE / filename, root / filename)
            (root / "vm.sh").write_text(BOUNDARY)
            (root / "vm-keys.py").write_text(KEYS)
            (home / "repo/packaging").mkdir()
            (home / "repo/packaging/stamp-installer.sh").write_text(STAMP)
            (home / "repo/packaging/stamp-installer.sh").chmod(0o755)
            (home / "vms/test").mkdir(parents=True)
            (root / "bin").mkdir()
            sleep = root / "bin/sleep"
            sleep.write_text("#!/bin/sh\nexit 0\n")
            sleep.chmod(0o755)
            result = subprocess.run(["bash", str(root / "fulltest.sh"), "test", mode], capture_output=True, text=True,
                env={**os.environ, "PF_VM_HOME": directory, "PF_PUBLIC": "", "FAULT": fault,
                     "PATH": str(root / "bin") + ":" + os.environ["PATH"]})
            calls = (home / "calls").read_text().splitlines()
            self.locked = (home / "vms/test/run.qcow2").exists()
            self.preserved = list((home / "vms/test").glob("failed-full-run-*.qcow2"))
            return result, calls

    def rejected(self, fault, message, mode="fresh"):
        result, calls = self.run_lane(fault, mode)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(message, result.stdout)
        self.assertIn("stop", calls)
        self.assertFalse(self.locked)
        self.assertEqual(len(self.preserved), 1)
        return result

    def test_fresh_passes_and_removes_overlay(self):
        result, calls = self.run_lane("none")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("FAIL", result.stdout)
        self.assertIn("done test (full profile, fresh)", result.stdout)
        self.assertIn("status: the stock profile", result.stdout)
        self.assertIn("the tiler: refused, it needs the fork", result.stdout)
        self.assertIn("stop", calls)
        self.assertFalse(self.locked)
        self.assertFalse(self.preserved)

    def test_switch_passes_and_uninstalls_from_the_full_profile(self):
        result, calls = self.run_lane("none", "switch")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("FAIL", result.stdout)
        self.assertIn("stock profile: the published installer", result.stdout)
        self.assertIn("plasma-fusion is the metapackage's build: 0.8.0-1.fc44", result.stdout)
        self.assertNotIn("--full-restore", result.stdout)
        self.assertIn("plasma-fusion-full is gone: none", result.stdout)
        self.assertFalse(self.preserved)

    def test_unknown_mode_is_refused_before_a_vm_starts(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(["bash", str(HERE / "fulltest.sh"), "test", "sideways"], capture_output=True,
                                    text=True, env={**os.environ, "PF_VM_HOME": directory})
            self.assertEqual(result.returncode, 2)
            self.assertFalse((Path(directory) / "results").exists())

    def test_dry_run_that_changes_something(self):
        self.rejected("dry-changes", "FAIL: the dry run")

    def test_half_a_fork(self):
        result = self.rejected("half-fork", "FAIL: the full profile's packages")
        self.assertIn("FAIL kwin-common is the pinned fork", result.stdout)

    def test_set_not_locked(self):
        result = self.rejected("no-lock", "FAIL: the full profile's packages")
        self.assertIn("FAIL kwin-libs is locked at the pin", result.stdout)

    def test_six_packages_that_are_not_the_metapackage_s_build(self):
        result = self.rejected("six-old", "FAIL: the full profile's packages")
        self.assertIn("FAIL plasma-fusion-quicklook is the metapackage's build: '0.7.0-1.fc44'", result.stdout)

    def test_restore_record_with_another_kwin(self):
        result = self.rejected("record-wrong", "FAIL: the full profile's packages")
        self.assertIn("FAIL the restore record keeps the stock kwin: '6.8.1-1.fc44'", result.stdout)

    def test_set_that_holds_without_the_lock(self):
        result = self.rejected("held-without-lock", "FAIL: the full profile's packages")
        self.assertIn("FAIL the lock leaves the solver nothing to skip", result.stdout)

    def test_status_with_a_note_on_the_full_profile(self):
        result = self.rejected("status-note", "FAIL: status on the full profile")
        self.assertIn("FAIL status: no note", result.stdout)

    def test_no_new_session_after_the_logout(self):
        result = self.rejected("no-session", "FAIL: no new session on tty1 after the logout")
        self.assertNotIn("the gated features on the fork", result.stdout)

    def test_no_desktop_after_the_uninstall(self):
        result = self.rejected("no-desktop", "FAIL: no Plasma session came up")
        self.assertNotIn("the previous desktop is back", result.stdout)

    def test_journal_that_cannot_be_read(self):
        self.rejected("kwinlog-fails", "FAIL: the journal of the session's KWin could not be read")

    def test_switcher_that_lands_on_no_test_window(self):
        result = self.rejected("switcher-elsewhere", "FAIL: the full profile's session")
        self.assertIn("FAIL the switcher did not switch to a test window", result.stdout)

    def test_restore_plan_that_names_another_kwin(self):
        result = self.rejected("plan-other-kwin", "FAIL: the stock KWin after --full-restore")
        self.assertIn("FAIL the plan names the recorded stock KWin", result.stdout)

    def test_lock_list_that_cannot_be_read(self):
        result = self.rejected("locklist-failed", "FAIL: the stock KWin after --full-restore")
        self.assertIn("FAIL the lock list could be read: 'failed'", result.stdout)

    def test_uninstall_that_leaves_a_package(self):
        result = self.rejected("uninstall-keeps-package", "FAIL: the uninstall")
        self.assertIn("FAIL plasma-fusion-settings: '0.8.0-1.fc44', expected 'none'", result.stdout)

    def test_uninstall_that_leaves_the_theme(self):
        result = self.rejected("theme-kept", "FAIL: the uninstall")
        self.assertIn("FAIL the previous desktop is back", result.stdout)

    def test_repository_that_is_switched_off(self):
        result = self.rejected("repo-disabled", "FAIL: the full profile's packages")
        self.assertIn("FAIL the full profile's repository is enabled: 'disabled'", result.stdout)

    def test_restore_that_leaves_the_repository_behind(self):
        result = self.rejected("restore-leaves-repo", "FAIL: the stock KWin after --full-restore")
        self.assertIn("FAIL the full profile's repository is gone: 'disabled'", result.stdout)

    def test_lock_that_does_not_hold(self):
        result = self.rejected("lock-loose", "FAIL: the full profile's packages")
        self.assertIn("FAIL a sync to the distribution's KWin finds nothing to do", result.stdout)

    def test_status_that_does_not_see_the_fork(self):
        result = self.rejected("status-blind", "FAIL: status on the full profile")
        self.assertIn("FAIL status: offscreen opacity, version 1", result.stdout)
        self.assertIn("FAIL status: no note", result.stdout)

    def test_idle_navigation_on_the_fork(self):
        result = self.rejected("nav-idle", "FAIL: the full profile's session")
        self.assertIn("FAIL navigation: the effect is not idle", result.stdout)

    def test_switcher_that_does_not_switch(self):
        result = self.rejected("switcher", "FAIL: the full profile's session")
        self.assertIn("FAIL the switcher did not switch", result.stdout)

    def test_tiler_without_a_session(self):
        result = self.rejected("tiler", "FAIL: the full profile's session")
        self.assertIn("FAIL the tiler: a session on the fork", result.stdout)

    def test_crash_on_the_full_profile(self):
        result = self.rejected("crash", "FAIL: the full profile's session")
        self.assertIn("FAIL crashes on the full profile", result.stdout)

    def test_restore_that_leaves_the_fork(self):
        result = self.rejected("restore-keeps-fork", "FAIL: the stock KWin after --full-restore")
        self.assertIn("FAIL kwin is the recorded stock one", result.stdout)

    def test_restore_that_takes_the_packages(self):
        result = self.rejected("restore-takes-six", "FAIL: the stock KWin after --full-restore")
        self.assertIn("FAIL plasma-fusion-navigation", result.stdout)

    def test_status_that_takes_the_restored_session_for_a_fork_by_hand(self):
        result = self.rejected("status-by-hand", "FAIL: the stock KWin after --full-restore")
        self.assertIn("FAIL status: the session still runs the KWin from before", result.stdout)
        self.assertIn("FAIL status: not taken for a fork installed by hand", result.stdout)

    def test_fallback_that_is_not_one(self):
        result = self.rejected("stock-nav-runs", "FAIL: Plasma Fusion on stock KWin after the restore")
        self.assertIn("FAIL navigation: the effect stays idle and says why", result.stdout)
        self.assertIn("FAIL navigation: nothing follows the gesture lock", result.stdout)

    def test_uninstall_that_leaves_the_lock(self):
        result = self.rejected("uninstall-leaves-lock", "FAIL: the uninstall")
        self.assertIn("FAIL kwin is not locked", result.stdout)

    def test_vm_that_does_not_come_up(self):
        self.rejected("wait", "FAIL: the VM did not come up")


if __name__ == "__main__":
    unittest.main()
