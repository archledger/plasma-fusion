#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The guest's side of fulltest.sh, copied into the VM and run there as the test user (the
# commands that talk to KWin: in the session's environment).
#
#   full-guest.sh facts            what the package system holds of the full profile, one
#                                  "KEY VALUE..." line each: pkg NAME EVR|none, lock NAME EVR,
#                                  record NAME EVR (the restore record), pin EVR and tag TAG (the
#                                  metapackage's record), repo enabled|disabled|no (the full
#                                  profile's repository as dnf sees it), recordfile yes|no
#   full-guest.sh kwinlog          the journal of the KWin this session runs
#   full-guest.sh active           the resource class of the active window (none without one)
#   full-guest.sh windows          opens Konsole, Dolphin and KWrite, one after the other
#   full-guest.sh close            closes them
#   full-guest.sh gesturelock      the gesture lock on and off again, as quick settings writes
#                                  it; the navigation effect answers in KWin's journal, when it
#                                  runs
#   full-guest.sh tile             the tiler's shortcut, as the key calls it
set -uo pipefail
SIX="plasma-fusion plasma-fusion-decoration plasma-fusion-settings plasma-fusion-navigation"
SIX="$SIX plasma-fusion-quicklook plasma-fusion-copytext"
RECORD=/var/lib/plasma-fusion/full-restore.txt
PROFILE=/usr/share/plasma-fusion/full-profile
APPS="konsole dolphin kwrite"

case ${1:-} in
  facts)
    for p in kwin kwin-common kwin-libs plasma-fusion-full $SIX; do
      if rpm -q "$p" >/dev/null 2>&1; then
        echo "pkg $p $(rpm -q --qf '%{VERSION}-%{RELEASE}' "$p")"
      else
        echo "pkg $p none"
      fi
    done
    # dnf5: "Package name: kwin" and, below it, "evr = 6.8.2-3.fc44.pf3"
    sudo dnf versionlock list 2>/dev/null |
      awk '/^Package name: / { name = $3 } /^evr = / { print "lock " name " " $3 }'
    sed -n 's/^\(kwin[a-z-]*\)=\(.*\)$/record \1 \2/p' "$RECORD" 2>/dev/null
    sed -n 's/^kwin=/pin /p; s/^tag=/tag /p' "$PROFILE" 2>/dev/null
    # The repository as dnf sees it: a file left with enabled=0 is no place updates come from,
    # and no repository that is gone either.
    if dnf -q repo list --enabled 2>/dev/null | grep -q 'plasma-fusion-full'; then
      echo "repo enabled"
    elif dnf -q repo list --all 2>/dev/null | grep -q 'plasma-fusion-full' || grep -qs 'plasma-fusion-full' /etc/yum.repos.d/*.repo; then
      echo "repo disabled"
    else
      echo "repo no"
    fi
    if [ -e "$RECORD" ]; then echo "recordfile yes"; else echo "recordfile no"; fi
    ;;
  kwinlog)
    pid=$(pgrep -u "$(id -u)" -x kwin_wayland | head -n 1)
    [ -n "$pid" ] || { echo "no kwin_wayland" >&2; exit 1; }
    journalctl --user -b --no-pager -o cat "_PID=$pid"
    ;;
  active)
    dir=$(mktemp -d) || exit 1
    echo 'console.info("pf-full-active " + (workspace.activeWindow ? workspace.activeWindow.resourceClass : "none"));' >"$dir/active.js"
    since=$(($(date +%s) - 1))
    busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting unloadScript s pf-full-active >/dev/null 2>&1
    id=$(busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting loadScript ss "$dir/active.js" pf-full-active | awk '{print $2}')
    case $id in '' | *[!0-9]*) rm -rf "$dir"; echo "KWin did not load the script" >&2; exit 1 ;; esac
    busctl --user call org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script run >/dev/null
    answer=
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      answer=$(journalctl --user --no-pager -o cat --since "@$since" | grep -a -o 'pf-full-active .*' | tail -n 1)
      [ -z "$answer" ] || break
      sleep 0.3
    done
    busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting unloadScript s pf-full-active >/dev/null 2>&1
    rm -rf "$dir"
    [ -n "$answer" ] || { echo "KWin did not answer" >&2; exit 1; }
    echo "${answer#pf-full-active }"
    ;;
  windows)
    for a in $APPS; do
      setsid -f "$a" >/dev/null 2>&1 </dev/null
      sleep 3
    done
    sleep 4
    for a in $APPS; do pgrep -u "$(id -u)" -x "$a" >/dev/null || { echo "$a did not start" >&2; exit 1; }; done
    ;;
  close)
    for a in $APPS; do pkill -u "$(id -u)" -x "$a"; done
    sleep 2
    ;;
  gesturelock)
    kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureLock --notify true
    sleep 2
    kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureLock --notify false
    sleep 2
    kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureLock --delete
    ;;
  tile)
    busctl --user call org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component invokeShortcut s \
      "Plasma Fusion: Tile Workspace" >/dev/null
    ;;
  *)
    echo "usage: full-guest.sh facts|kwinlog|active|windows|close|gesturelock|tile" >&2
    exit 2
    ;;
esac
