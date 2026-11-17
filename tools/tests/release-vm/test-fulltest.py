#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""fulltest.sh against a stand-in VM: the full profile's lane passes on a system that behaves as
the installer promises (fresh, switch and update), and a system that does not fails the run,
stops the VM and keeps the overlay. The faults, one test each: a dry run that changes something;
a set that is
half the fork, not locked, not the metapackage's build (by version, or by the repository it came
from: #197), or whose restore record is wrong; a repository that is there and switched off; a set
that holds without the lock; a lock list that cannot be read; a status that does not see the fork
or carries a note; no new session after the logout, or no desktop after it; a start-up that does
not end, or whose state cannot be read; an idle navigation effect; a journal that cannot be read; a switcher that does not switch, or lands on no test
window; a tiler without a session; a restore whose plan names another KWin, that leaves the fork
or the repository, or takes the packages; in switch mode a record directory that is not root's
alone; a status that takes the session after the restore for a fork installed by hand; a note
after the restore (any on a stock KWin of the pin's version, any but the two rebuild notes on a
newer one: #198; the decoration's compares with the installed KDecoration and not with KWin,
#194) or on the full profile but the decoration part's; on a newer stock KWin no navigation
rebuild note, or a navigation effect that gives the capability as its reason; a fallback that is
not one; a crash; an uninstall that leaves the lock or a package, or the theme; a VM that does not
come up; a plan that enables another Copr project than the stamped one. In update mode (from the
last release's full profile, the live project's, to a candidate's): a move that leaves the live
project, enables no candidate project or takes the lock; an update plan that keeps the lock or
installs apart, or whose dry run changes something; an update in two transactions, that leaves
the KWin packages or the lock at the old pin, loses the restore record, takes the six from the
live project or ends at another pin than the stamp's; a lock that does not hold after it; a login
after it in safe mode; and a stamp without a pin. Not every check of the lane has a fault: its
plumbing (the copies into the VM, a collector that cannot count), the plan's wording and update's
check that its transaction is a new one are covered by the passing runs only. Of the stamp, the
tests check the Copr project it is given (the live one by default, a candidate's own when named:
issue #178) and that the lock check leaves out that project's repository by its exact id."""
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
# The last release's full profile, where update starts: its pin (FAKE_OLD_PIN: the same as the
# candidate's, a release without a new fork tag), its fork tag and the live project it came from.
OLD_PIN=${FAKE_OLD_PIN:-6.8.1-1.fc44.pf2} OLD_TAG=v6.8.1-pf2
LIVE_ID=copr:copr.fedorainfracloud.org:archledger:plasma-fusion-full
updated() { [ "$(get updated no)" = yes ]; }
# The upstream version of an EVR; FAKE_STOCK newer than the pin's is Fedora's KWin past the pin (#198).
up() { local e=${1#*:}; echo "${e%%-*}"; }
SIX="plasma-fusion plasma-fusion-decoration plasma-fusion-settings plasma-fusion-navigation plasma-fusion-quicklook plasma-fusion-copytext"
facts() {
  local installed p kwin=$STOCK six=none full=no meta=$META pin=$PIN tag=v6.8.2-pf3
  installed=$(get installed stock)
  case $installed in
    six) six=$RELEASED ;;
    full) kwin=$PIN six=$META full=yes ;;
    released-full) kwin=$OLD_PIN six=$RELEASED full=yes meta=$RELEASED pin=$OLD_PIN tag=$OLD_TAG ;;
    restored) six=$META ;;
  esac
  [ "$FAULT" = update-old-kwin ] && [ "$installed" = full ] && updated && kwin=$OLD_PIN
  [ "$FAULT" = restore-keeps-fork ] && [ "$installed" = restored ] && kwin=$PIN
  [ "$FAULT" = restore-takes-six ] && [ "$installed" = restored ] && six=none
  [ "$FAULT" = six-old ] && [ "$installed" = full ] && six=$RELEASED
  for p in kwin kwin-common kwin-libs; do
    if [ "$FAULT" = half-fork ] && [ "$p" = kwin-common ]; then echo "pkg $p $STOCK"; else echo "pkg $p $kwin"; fi
  done
  if [ "$full" = yes ]; then echo "pkg plasma-fusion-full $meta"; else echo "pkg plasma-fusion-full none"; fi
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
          [ "$FAULT" != six-from-stock ] || from=$stock_id
          [ "$FAULT" != update-from-live ] || ! updated || from=$LIVE_ID ;;
    released-full) from=$LIVE_ID ;;
    six | restored) from=$stock_id ;;
    *) from= ;;
  esac
  [ -z "$from" ] || for p in $SIX; do echo "from $p $from"; done
  # rpm's transaction ids: the stock system's, the stock profile's, the release's --full, a --full
  # or an update (the KWin packages stay where the pin does not move), the restore, the uninstall.
  local tk=100 ts=''
  case $installed in
    six) ts=150 ;;
    released-full) tk=200 ts=200 ;;
    full) tk=300 ts=300
      if updated && { [ "$OLD_PIN" = "$PIN" ] || [ "$FAULT" = update-old-kwin ]; }; then tk=200; fi
      ;;
    restored) tk=400 ts=300 ;;
    gone) tk=500 ;;
  esac
  # update-split: the metapackage with the KWin it pulls, the six packages in a transaction apart.
  local tm=$ts
  [ "$FAULT" != update-split ] || ! updated || ts=301
  for p in kwin kwin-common kwin-libs; do echo "tid $p $tk"; done
  [ "$full" != yes ] || echo "tid plasma-fusion-full $tm"
  [ -z "$ts" ] || for p in $SIX; do echo "tid $p $ts"; done
  if [ "$FAULT" = locklist-failed ] && [ "$installed" = restored ]; then echo "locklist failed"; else echo "locklist ok"; fi
  if [ "$full" = yes ]; then
    local lockpin=$kwin
    [ "$FAULT" != update-old-lock ] || ! updated || lockpin=$OLD_PIN
    # move-drops-lock: the move takes the lock away, and the update puts it back.
    if [ "$(get lockless no)" = no ] || updated; then
      for p in kwin kwin-common kwin-libs; do
        [ "$FAULT" = no-lock ] && [ "$p" = kwin-libs ] || echo "lock $p $lockpin"
      done
    fi
    for p in kwin kwin-common kwin-libs; do
      if [ "$FAULT" = update-record-lost ] && updated; then :
      elif [ "$FAULT" = record-wrong ] && [ "$p" = kwin ]; then echo "record $p 6.8.1-1.fc44"; else echo "record $p $STOCK"; fi
    done
    echo "pin $pin"; echo "tag $tag"; echo "recordfile yes"
    # The projects the VM has, once update's steps say (the release's --full, the move); before
    # that the stamped project is the one it has.
    if [ "$FAULT" = repo-disabled ]; then echo "repo disabled"
    elif [ -s "$S/enabled" ]; then
      case " $(get enabled '') " in *" $repo "*) echo "repo enabled" ;; *) echo "repo no" ;; esac
    else echo "repo enabled"; fi
  else
    [ "$FAULT" = uninstall-leaves-lock ] && [ "$installed" = gone ] && echo "lock kwin $PIN"
    echo "recordfile no"
    if [ "$FAULT" = restore-leaves-repo ] && [ "$installed" = restored ]; then echo "repo disabled"; else echo "repo no"; fi
  fi
}
status() {
  local installed running deco
  installed=$(get installed stock) running=$(get running stock)
  local fullnow=no
  case $installed in full | released-full) fullnow=yes ;; esac
  echo "Plasma Fusion 0.8.0 (/usr/share/plasma-fusion)"
  if [ "$installed" = full ]; then
    echo "  profile: full (the maintained KWin fork, pinned at $PIN, fork tag v6.8.2-pf3)"
  elif [ "$installed" = released-full ]; then
    echo "  profile: full (the maintained KWin fork, pinned at $OLD_PIN, fork tag $OLD_TAG)"
  else
    echo "  profile: stock (the distribution's KWin)"
  fi
  if [ "$running" = fork ] && [ "$FAULT" != status-blind ]; then
    echo "  the running KWin's capabilities:"
    echo "    thumbnail source lifecycle: version 1"
    echo "    offscreen opacity: version 1"
    echo "    transient tiling (dynamic tiling): yes"
    if [ "$fullnow" != yes ] && [ "$FAULT" = status-by-hand ]; then
      echo "  note: this KWin advertises the fork's capabilities without the full profile (a fork installed by hand)"
    elif [ "$fullnow" != yes ]; then
      echo "  note: the full profile is not installed and the running KWin still advertises the fork's capabilities:"
      echo "        log out and in (the KWin on the disk was put there after this session's KWin started, as after --full-restore)"
    fi
    [ "$FAULT" != status-note ] || [ "$installed" != full ] || echo "  note: run 'plasma-fusion update' to apply this version's settings"
  else
    echo "  the running KWin's capabilities: none of the fork's (every feature uses its stock fallback)"
    if [ "$fullnow" = yes ]; then
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
    six | full | released-full | restored)
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
  # The release (from before #199) recorded no KWin version: on a stock KWin of another version
  # than its pin, its login is in safe mode. After an update the new installer has recorded it.
  if [ "$installed" = released-full ] && [ "$(up "$STOCK")" != "$(up "$OLD_PIN")" ]; then
    echo "  switched off: the navigation part, the decoration part (why: kwin $(up "$STOCK") -> $(up "$OLD_PIN"))"
  elif [ "$FAULT" = update-safe-mode ] && [ "$installed" = full ] && updated; then
    echo "  switched off: the navigation part (why: kwin $(up "$OLD_PIN") -> $(up "$PIN"))"
  else
    echo "  switched off: nothing"
  fi
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
      *'install-release.sh --full --yes'*) put installed released-full; put enabled archledger/plasma-fusion-full ;;
      *'copr remove archledger/plasma-fusion-full '*)
        target=$(printf '%s\n' "$*" | sed -n 's/.*copr enable \([^ ]*\) .*/\1/p')
        case $FAULT in
          move-leaves-live) put enabled "archledger/plasma-fusion-full $target" ;;
          move-no-enable) put enabled - ;;
          move-drops-lock) put enabled "$target"; put lockless yes ;;
          *) put enabled "$target" ;;
        esac ;;
      *'install.sh update --dry-run'*)
        [ "$FAULT" != update-dry-changes ] || { put installed full; put updated yes; }
        [ "$FAULT" = update-plan-no-unlock ] ||
          echo "  sudo dnf -y versionlock delete kwin kwin-common kwin-libs   (the pin goes first: it would hold KWin at the old fork)"
        echo "  sudo dnf -y upgrade --refresh $SIX plasma-fusion-full   (the metapackage pulls the new pin)"
        [ "$FAULT" != update-plan-apart ] || echo "  sudo dnf -y install plasma-fusion-extra   (new in this release)"
        echo "  sudo dnf -y versionlock add kwin kwin-common kwin-libs   (the pin again, at the new fork)"
        echo "  plasma-fusion update   (as you, in this session; it backs up first)" ;;
      *'install.sh update --yes'*) put installed full; put updated yes ;;
      *'org.kde.Shutdown logout'*)
        case $(get installed stock) in full | released-full) put running fork ;; *) put running stock ;; esac ;;
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
          six | full | released-full | restored) echo "LookAndFeelPackage=org.plasmafusion.dark.desktop" ;;
          gone)
            if [ "$FAULT" = theme-kept ]; then
              echo "LookAndFeelPackage=org.plasmafusion.dark.desktop"
            else
              echo "LookAndFeelPackage=org.kde.breeze.desktop"
            fi ;;
          *) echo "LookAndFeelPackage=org.kde.breeze.desktop" ;;
        esac ;;
      *'date +%s'*) echo 100 ;;
      *'is-active plasma-ksplash.service'*)
        n=$(bump splashprobe)
        case $FAULT in
          splash-stuck) echo activating ;;
          splash-unreadable) exit 1 ;;
          splash-unreadable-once) if [ "$n" = 1 ]; then exit 1; else echo inactive; fi ;;
          *) echo inactive ;;
        esac ;;
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
# FAKE_STAMP_PIN: another pin than the project's builds have (empty: none at all).
printf "PF_VERSION='0.8.0'\nPF_FULL_FEDORA='44'\nPF_FULL_REPO='%s'\nPF_FULL_PIN='%s'\n" "$repo" "${FAKE_STAMP_PIN-6.8.2-3.fc44.pf3}" >"$1"
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

    # ---- update: from the last release's full profile to a candidate's (ADR 0001's round) ----
    CAND = {"PF_FULL_REPO": "archledger/plasma-fusion-full-candidates"}

    def test_update_passes_and_moves_the_pin_in_one_transaction(self):
        result, calls = self.run_lane("none", "update", env_extra=self.CAND)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("FAIL", result.stdout)
        self.assertIn("done test (full profile, update)", result.stdout)
        # The release, from the live project, at its own pin; its safe mode logged, not checked.
        self.assertIn("ok   kwin is the pinned fork: 6.8.1-1.fc44.pf2", result.stdout)
        self.assertIn("ok   plasma-fusion comes from the full profile's repository: "
                      "copr:copr.fedorainfracloud.org:archledger:plasma-fusion-full", result.stdout)
        self.assertIn("the release's login check: switched off: the navigation part", result.stdout)
        self.assertIn("ok   the release's project is gone: no", result.stdout)
        # The update: the new pin, locked, from the candidate's project, in one transaction.
        self.assertIn("ok   the plan: the lock off, one upgrade, the lock on", result.stdout)
        self.assertIn("ok   one rpm transaction took the update (10 packages); others: (none)", result.stdout)
        self.assertIn("ok   kwin is locked at the pin: 6.8.2-3.fc44.pf3", result.stdout)
        self.assertIn("ok   plasma-fusion comes from the full profile's repository: "
                      "copr:copr.fedorainfracloud.org:archledger:plasma-fusion-full-candidates", result.stdout)
        self.assertIn("ok   the restore record keeps the stock kwin: 6.8.2-3.fc44", result.stdout)
        self.assertIn("ok   the login check switched nothing off", result.stdout)
        # Back by uninstall on the full system, as in switch.
        self.assertIn("plasma-fusion-full is gone: none", result.stdout)
        self.assertNotIn("--full-restore", result.stdout)
        self.assertFalse(self.preserved)

    def test_update_without_a_new_pin_leaves_the_kwin_packages(self):
        # A release without a new fork tag: the six and the metapackage move, the KWin packages
        # stay in the transaction they came with.
        env = {**self.CAND, "FAKE_OLD_PIN": "6.8.2-3.fc44.pf3"}
        result, _ = self.run_lane("none", "update", env_extra=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("ok   one rpm transaction took the update (7 packages); others: (none)", result.stdout)
        self.assertIn("ok   kwin-libs stays as it was (the pin did not move): 200", result.stdout)

    def test_update_from_the_live_project_is_refused_before_a_vm_starts(self):
        # The live project holds the release the round starts from, and the published installer
        # would update nothing: update needs a candidate's project and this tree's installer.
        for env in ({}, {"PF_FULL_REPO": "archledger/plasma-fusion-full"},
                    {**self.CAND, "PF_PUBLIC": "1"}):
            with self.subTest(env=env), tempfile.TemporaryDirectory() as directory:
                result = subprocess.run(["bash", str(HERE / "fulltest.sh"), "test", "update"], capture_output=True,
                                        text=True, env={**os.environ, "PF_VM_HOME": directory, "PF_PUBLIC": "", **env})
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertFalse((Path(directory) / "results").exists())

    def test_update_s_dry_run_that_changes_something(self):
        self.rejected("update-dry-changes", "FAIL: the dry run", "update", self.CAND)

    def test_update_plan_that_keeps_the_lock(self):
        result = self.rejected("update-plan-no-unlock", "FAIL: the dry run", "update", self.CAND)
        self.assertIn("FAIL the plan: the lock off, one upgrade, the lock on: 'upgrade --refresh,versionlock add'",
                      result.stdout)

    def test_update_plan_that_installs_apart(self):
        result = self.rejected("update-plan-apart", "FAIL: the dry run", "update", self.CAND)
        self.assertIn("FAIL the plan: the lock off, one upgrade, the lock on", result.stdout)

    def test_update_in_two_transactions(self):
        result = self.rejected("update-split", "FAIL: the full profile's packages after the update", "update", self.CAND)
        self.assertIn("FAIL one rpm transaction took the update (10 packages); others: 'plasma-fusion plasma-fusion-decoration",
                      result.stdout)

    def test_update_that_leaves_kwin_at_the_old_pin(self):
        result = self.rejected("update-old-kwin", "FAIL: the full profile's packages after the update", "update", self.CAND)
        self.assertIn("FAIL kwin is the pinned fork: '6.8.1-1.fc44.pf2', expected '6.8.2-3.fc44.pf3'", result.stdout)
        self.assertIn("FAIL one rpm transaction took the update (10 packages); others: 'kwin kwin-common kwin-libs'",
                      result.stdout)

    def test_update_that_leaves_the_lock_at_the_old_pin(self):
        result = self.rejected("update-old-lock", "FAIL: the full profile's packages after the update", "update", self.CAND)
        self.assertIn("FAIL kwin is locked at the pin: '6.8.1-1.fc44.pf2'", result.stdout)

    def test_update_that_loses_the_restore_record(self):
        result = self.rejected("update-record-lost", "FAIL: the full profile's packages after the update", "update",
                               self.CAND)
        self.assertIn("FAIL the restore record keeps the stock kwin: '', expected '6.8.2-3.fc44'", result.stdout)

    def test_update_from_the_release_s_project(self):
        result = self.rejected("update-from-live", "FAIL: the full profile's packages after the update", "update",
                               self.CAND)
        self.assertIn("FAIL plasma-fusion comes from the full profile's repository: "
                      "'copr:copr.fedorainfracloud.org:archledger:plasma-fusion-full'", result.stdout)

    def test_move_that_leaves_the_release_s_project(self):
        result = self.rejected("move-leaves-live", "FAIL: the move to the candidate's project", "update", self.CAND)
        self.assertIn("FAIL the release's project is gone: 'enabled', expected 'no'", result.stdout)
        self.assertNotIn("installer: update --dry-run", result.stdout)

    def test_update_to_another_pin_than_this_tree_s(self):
        # The project's builds pin another fork than the tree's spec: the update ends there.
        result = self.rejected("none", "FAIL: the full profile's packages after the update", "update",
                               {**self.CAND, "FAKE_STAMP_PIN": "6.8.3-1.fc44.pf1"})
        self.assertIn("FAIL the metapackage's record names this tree's pin: '6.8.2-3.fc44.pf3', expected '6.8.3-1.fc44.pf1'",
                      result.stdout)

    def test_update_whose_lock_does_not_hold(self):
        result = self.rejected("lock-loose", "FAIL: the full profile's packages after the update", "update", self.CAND)
        self.assertIn("FAIL a sync to the distribution's KWin finds nothing to do", result.stdout)

    def test_update_with_a_stamp_without_a_pin_stops_before_a_vm_starts(self):
        result, calls = self.run_lane("none", "update", env_extra={**self.CAND, "FAKE_STAMP_PIN": ""})
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("FAIL: the stamped installer names no pin to update to", result.stdout)
        self.assertNotIn("start", calls)

    def test_move_that_does_not_enable_the_candidate_s_project(self):
        result = self.rejected("move-no-enable", "FAIL: the move to the candidate's project", "update", self.CAND)
        self.assertIn("FAIL the candidate's project is enabled: 'no', expected 'enabled'", result.stdout)

    def test_move_that_takes_the_lock(self):
        result = self.rejected("move-drops-lock", "FAIL: the move to the candidate's project", "update", self.CAND)
        self.assertIn("FAIL the move changed no package, lock or record (07-packages.txt and 06-packages.txt differ)",
                      result.stdout)

    def test_update_whose_login_is_in_safe_mode(self):
        result = self.rejected("update-safe-mode", "FAIL: status on the full profile", "update", self.CAND)
        self.assertIn("FAIL the login check switched nothing off", result.stdout)

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
        # Stock KWin at the pin's version: the navigation part's record names that KWin, so a
        # rebuild note for it is wrong - only the decoration's (which compares Fedora's
        # KDecoration, #194) is allowed there.
        result = self.rejected("restored-stale-build", "FAIL: status after the restore")
        self.assertIn("FAIL status: no note but the decoration part's rebuild note", result.stdout)

    def test_restored_with_a_decoration_built_against_another_kdecoration(self):
        # Fedora's KDecoration moves with Fedora's updates, independently of the pin: on a stock
        # KWin of the pin's version the decoration's rebuild note is right, and the lane passes.
        result, _ = self.run_lane("none", "fresh", env_extra={"FAKE_DECO_BUILT": "6.8.3"})
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("ok   status: no note but the decoration part's rebuild note", result.stdout)

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

    def test_start_up_that_does_not_end(self):
        # The splash still up: the session's start-up has not ended, and no check runs in it.
        result = self.rejected("splash-stuck", "FAIL: the session's start-up did not end (the splash still activating after 90 s)")
        self.assertNotIn("screenshot 01-stock", result.stdout)

    def test_start_up_state_that_cannot_be_read(self):
        # No state read is no end of the start-up: the lane does not go on.
        result = self.rejected("splash-unreadable", "FAIL: the session's start-up state could not be read")
        self.assertNotIn("screenshot 01-stock", result.stdout)

    def test_start_up_state_read_again_after_a_failed_probe(self):
        # A probe that failed once (ssh, the user's service manager) is no end: the next one is.
        result, _ = self.run_lane("splash-unreadable-once")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("FAIL", result.stdout)

    def test_vm_that_does_not_come_up(self):
        self.rejected("wait", "FAIL: the VM did not come up")


if __name__ == "__main__":
    unittest.main()
