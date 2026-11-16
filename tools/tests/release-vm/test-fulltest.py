#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""fulltest.sh against a stand-in VM: the full profile's lane passes on a system that behaves as
the installer promises (fresh and switch), and a system that does not fails the run, stops the VM
and keeps the overlay. The faults, one test each: a dry run that changes something; a set that is
half the fork, not locked, not the metapackage's build (by version, or by the repository it came
from: #197), or whose restore record is wrong; a repository that is there and switched off; a set
that holds without the lock; a lock list that cannot be read; a status that does not see the fork
or carries a note; no new session after the logout, or no desktop after it; an idle navigation
effect; a journal that cannot be read; a switcher that does not switch, or lands on no test
window; a tiler without a session; a restore whose plan names another KWin, that leaves the fork
or the repository, or takes the packages; in switch mode a record directory that is not root's
alone; a status that takes the session after the restore for a fork installed by hand; a note
after the restore (any on a stock KWin of the pin's version, any but the two rebuild notes on a
newer one: #198; the decoration's compares with the installed KDecoration and not with KWin,
#194) or on the full profile but the decoration part's; on a newer stock KWin no navigation
rebuild note, or a navigation effect that gives the capability as its reason; a fallback that is
not one; a crash; an uninstall that leaves the lock or a package, or the theme; a VM that does not
come up; a plan that enables another Copr project than the stamped one. Not every check of the
lane has a fault: its plumbing (the copies
into the VM, a collector that cannot count) and the plan's wording are covered by the passing
runs only. Of the stamp, the tests check the Copr project it is given (the live one by default, a
candidate's own when named: issue #178) and that the lock check leaves out that project's
repository by its exact id."""
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
STOCK=${FAKE_STOCK:-6.8.2-3.fc44} PIN=6.8.2-3.fc44.pf3 META=0.8.0-1.fc44 RELEASED=0.7.0-1.fc44
# The upstream version of an EVR; FAKE_STOCK newer than the pin's is Fedora's KWin past the pin (#198).
up() { local e=${1#*:}; echo "${e%%-*}"; }
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
  # The repository each of the six came from (the guest's dnf repoquery --installed): the full
  # profile's project, named on the command line as the real guest gets it, or the stock one.
  local repo from stock_id=copr:copr.fedorainfracloud.org:archledger:plasma-fusion
  repo=$(printf '%s\n' "${1:-}" | sed -n 's/.*full-guest\.sh facts \([^ ]*\).*/\1/p')
  case $installed in
    full) from="copr:copr.fedorainfracloud.org:${repo%%/*}:${repo#*/}"
          [ "$FAULT" != six-from-stock ] || from=$stock_id ;;
    six | restored) from=$stock_id ;;
    *) from= ;;
  esac
  [ -z "$from" ] || for p in $SIX; do echo "from $p $from"; done
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
  local installed running deco
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
  # The compiled parts' rebuild notes, as status makes them (#194, #198): the decoration's record
  # holds the KDecoration the build compiled against - FAKE_DECO_BUILT, the pin's version by
  # default (a full build from before Fedora's update) - compared with the installed one, which is
  # Fedora's and moves with stock KWin; the navigation part's holds the KWin it was built for,
  # compared with the running one.
  case $(get installed stock) in
    six | full | restored)
      deco=${FAKE_DECO_BUILT:-$(up "$PIN")}
      [ "$deco" = "$(up "$STOCK")" ] ||
        echo "  note: the decoration part was built against $deco, the installed KDecoration is $(up "$STOCK"): update or rebuild that package" ;;
  esac
  if [ "$installed" = restored ] && [ "$running" != fork ] && [ "$(up "$STOCK")" != "$(up "$PIN")" ]; then
    [ "$FAULT" = stock-newer-no-nav-note ] ||
      echo "  note: the navigation part was built against $(up "$PIN"), KWin is $(up "$STOCK"): update or rebuild that package"
    [ "$FAULT" != stock-newer-other-note ] || echo "  note: run 'plasma-fusion update' to apply this version's settings"
  fi
  # A part built for an older KWin of the same series as stock: a rebuild due, whatever the pin.
  if [ "$FAULT" = restored-stale-build ] && [ "$installed" = restored ] && [ "$running" != fork ]; then
    echo "  note: the navigation part was built against 6.8.1, KWin is $(up "$STOCK"): update or rebuild that package"
  fi
  echo "  switched off: nothing"
}
case "$cmd" in
  start) printf overlay >"$PF_VM_HOME/vms/$name/run.qcow2" ;;
  wait) [ "$FAULT" != wait ] ;;
  stop|shot) exit 0 ;;
  ssh)
    case "$*" in
      *'full-guest.sh facts'*) facts "$*" ;;
      *'full-guest.sh kwinlog'*)
        [ "$FAULT" != kwinlog-fails ] || { echo "no kwin_wayland" >&2; exit 1; }
        if [ "$(get running stock)" = fork ]; then
          [ "$FAULT" != nav-idle ] || echo "plasmafusion-navigation: compositor lacks offscreen opacity capability version 1; the effect stays idle"
          [ "$FAULT" = nav-idle ] || printf 'plasmafusion-navigation: gesture lock on\nplasmafusion-navigation: gesture lock off\n'
        else
          if [ "$(up "$STOCK")" != "$(up "$PIN")" ] && [ "$FAULT" != stock-newer-nav-capability ] && [ "$FAULT" != stock-nav-runs ]; then
            echo "plasmafusion-navigation: built for KWin $(up "$PIN"), running $(up "$STOCK"): the effect stays idle"
          else
            [ "$FAULT" = stock-nav-runs ] || echo "plasmafusion-navigation: compositor lacks offscreen opacity capability version 1; the effect stays idle"
          fi
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
      *'install -d -m 0700 /var/lib/plasma-fusion'*) put hidden yes ;;
      *'cat /var/lib/plasma-fusion/full-restore.txt'*)
        if [ "$(get hidden no)" = no ] || [ "$FAULT" = record-readable ]; then echo readable; else echo hidden; fi ;;
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
        echo "  sudo dnf -y copr enable ${PLAN_REPO:-archledger/plasma-fusion-full} fedora-44-x86_64"
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
        echo "distro-sync $*" >>"$PF_VM_HOME/calls"
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
echo "stamp $*" >>"$PF_VM_HOME/calls"
repo=archledger/plasma-fusion-full
while [ $# -gt 1 ]; do
  case $1 in --full-repo) repo=$2; shift ;; esac
  shift
done
printf "PF_VERSION='0.8.0'\nPF_FULL_FEDORA='44'\nPF_FULL_REPO='%s'\nPF_FULL_PIN='6.8.2-3.fc44.pf3'\n" "$repo" >"$1"
'''
KEYS = r'''#!/usr/bin/env python3
import sys
for step in sys.argv[2:]:
    if step.startswith("shot:"):
        open(step[5:], "w").write("png")
'''


class FullLaneTest(unittest.TestCase):
    def run_lane(self, fault, mode="fresh", env_extra=None):
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
                     "PATH": str(root / "bin") + ":" + os.environ["PATH"], **(env_extra or {})})
            calls = (home / "calls").read_text().splitlines()
            self.locked = (home / "vms/test/run.qcow2").exists()
            self.preserved = list((home / "vms/test").glob("failed-full-run-*.qcow2"))
            return result, calls

    def rejected(self, fault, message, mode="fresh", env_extra=None):
        result, calls = self.run_lane(fault, mode, env_extra)
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
        self.assertIn("the restore record's directory is root's alone", result.stdout)
        self.assertIn("ok   the record is where the user cannot read it, and read all the same: hidden 6.8.2-3.fc44", result.stdout)
        self.assertFalse(self.preserved)

    def test_switch_whose_record_directory_was_not_made_root_s(self):
        result = self.rejected("record-readable", "FAIL: the full profile's packages", "switch")
        self.assertIn("FAIL the record is where the user cannot read it, and read all the same: 'readable 6.8.2-3.fc44'", result.stdout)

    def test_candidates_project_reaches_the_stamp_and_the_plan(self):
        # A candidate is tested from a Copr project of its own (issue #178): the lane stamps the
        # project it is given, and the plan it checks enables exactly that one.
        cand = "archledger/plasma-fusion-full-candidates"
        result, calls = self.run_lane("none", env_extra={"PF_FULL_REPO": cand, "PLAN_REPO": cand})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("FAIL", result.stdout)
        self.assertTrue([c for c in calls if c.startswith("stamp ") and "--full-repo " + cand in c], calls)

    def test_live_project_is_stamped_by_default(self):
        result, calls = self.run_lane("none")
        self.assertTrue([c for c in calls if c.startswith("stamp ") and "--full-repo archledger/plasma-fusion-full " in c], calls)

    def test_plan_enabling_another_project_than_the_stamped_one_fails(self):
        # The candidates' project stamped, the plan naming the live one: the lane must not pass,
        # although one name is a prefix of the other.
        self.rejected("none", "the plan enables the full profile's repository",
                      env_extra={"PF_FULL_REPO": "archledger/plasma-fusion-full-candidates"})

    def test_lock_check_leaves_out_exactly_the_stamped_project(self):
        # The sync that shows the lock holding leaves the stamped project out by its whole Copr
        # repository id: a pattern that missed it would let dnf find the fork there and pass.
        cand = "archledger/plasma-fusion-full-candidates"
        for project, env in (("archledger/plasma-fusion-full", {}),
                             (cand, {"PF_FULL_REPO": cand, "PLAN_REPO": cand})):
            with self.subTest(project=project):
                result, calls = self.run_lane("none", env_extra=env)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                syncs = [c for c in calls if c.startswith("distro-sync ")]
                self.assertTrue(syncs, calls)
                owner, name = project.split("/")
                for c in syncs:
                    self.assertIn("--disablerepo='copr:copr.fedorainfracloud.org:%s:%s' " % (owner, name), c)

    def test_malformed_project_is_refused_before_a_vm_starts(self):
        for value in ("archledger", "archledger/x y", "archledger/x;reboot", "a/b/c"):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as directory:
                result = subprocess.run(["bash", str(HERE / "fulltest.sh"), "test", "fresh"], capture_output=True,
                                        text=True, env={**os.environ, "PF_VM_HOME": directory, "PF_PUBLIC": "",
                                                        "PF_FULL_REPO": value})
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertFalse((Path(directory) / "results").exists())

    def test_public_run_with_another_project_is_refused_before_a_vm_starts(self):
        # The published installer names the live project: a public run cannot test another one.
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(["bash", str(HERE / "fulltest.sh"), "test", "fresh"], capture_output=True,
                                    text=True, env={**os.environ, "PF_VM_HOME": directory, "PF_PUBLIC": "1",
                                                    "PF_FULL_REPO": "archledger/plasma-fusion-full-candidates"})
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertFalse((Path(directory) / "results").exists())

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

    def test_stock_kwin_newer_than_the_pin_passes(self):
        # Fedora's KWin past the pin (6.8.3 against 6.8.2-pf3, #198): after the restore the parts
        # built for the pin's KWin are due for a rebuild, and the navigation effect stays idle on
        # its version check; both modes pass.
        # A decoration built against the newer KDecoration (a full build made after the update)
        # has no note of its own.
        for mode, deco in (("fresh", None), ("fresh", "6.8.3"), ("switch", None)):
            with self.subTest(mode=mode, decoration_built_against=deco):
                env = {"FAKE_STOCK": "6.8.3-1.fc44"}
                if deco:
                    env["FAKE_DECO_BUILT"] = deco
                result, calls = self.run_lane("none", mode, env_extra=env)
                self.assertEqual(result.returncode, 0, result.stdout)
                if mode == "fresh":  # the switch lane has no restore: it uninstalls from the fork
                    self.assertIn("ok   status: the navigation part's rebuild note (built for the pin's KWin 6.8.2)", result.stdout)
                    self.assertIn("ok   status: no note but the rebuild notes of the parts built for KWin 6.8.2", result.stdout)
                    self.assertIn("ok   navigation: the effect stays idle, built for the pin's KWin 6.8.2", result.stdout)

    def test_a_stale_build_after_the_restore_on_the_pin_s_version(self):
        # Stock KWin at the pin's version: no note at all after the restore, a rebuild note included.
        result = self.rejected("restored-stale-build", "FAIL: status after the restore")
        self.assertIn("FAIL status: no note", result.stdout)

    def test_stock_newer_without_the_navigation_rebuild_note(self):
        # Built against the pin's KWin, the navigation part is due for a rebuild on a newer stock
        # KWin: a status without that note does not see it.
        result = self.rejected("stock-newer-no-nav-note", "FAIL: status after the restore",
                               env_extra={"FAKE_STOCK": "6.8.3-1.fc44"})
        self.assertIn("FAIL status: the navigation part's rebuild note (built for the pin's KWin 6.8.2)", result.stdout)

    def test_stock_newer_with_another_note(self):
        result = self.rejected("stock-newer-other-note", "FAIL: status after the restore",
                               env_extra={"FAKE_STOCK": "6.8.3-1.fc44"})
        self.assertIn("FAIL status: no note but the rebuild notes of the parts built for KWin 6.8.2", result.stdout)

    def test_stock_newer_navigation_that_gives_the_capability_reason(self):
        result = self.rejected("stock-newer-nav-capability", "FAIL: Plasma Fusion on stock KWin after the restore",
                               env_extra={"FAKE_STOCK": "6.8.3-1.fc44"})
        self.assertIn("FAIL navigation: the effect stays idle, built for the pin's KWin 6.8.2", result.stdout)

    def test_six_packages_that_are_not_the_metapackage_s_build(self):
        result = self.rejected("six-old", "FAIL: the full profile's packages")
        self.assertIn("FAIL plasma-fusion-quicklook is the metapackage's build: '0.7.0-1.fc44'", result.stdout)

    def test_six_packages_from_the_stock_project(self):
        # The two projects can build the same version: after a switch from the stock profile
        # the six must still be the full project's builds, not only its version (#197).
        result = self.rejected("six-from-stock", "FAIL: the full profile's packages")
        self.assertIn("FAIL plasma-fusion-navigation comes from the full profile's repository: "
                      "'copr:copr.fedorainfracloud.org:archledger:plasma-fusion'", result.stdout)

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
