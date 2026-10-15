#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Dynamic workspaces (plasmafusion-workspaces) in a private session. The Fusion setup runs first (its
# four named workspaces Work, Design, Media, Chat), one window is open on Work, then the user turns
# the script on (KeepFirst 0) and:
#   1. nothing is removed during the first ten seconds (a session restore's windows look for their
#      desktops), then the empty ones go except the one after the last occupied: Work, Design;
#   2. a window moved to the last workspace: a new empty one is added at once, "Workspace 3";
#   3. switching to the window's workspace: the empty first one goes - not before a second after
#      the switch (KWin's slide) - and "Workspace 3" is renumbered "Workspace 2";
#   4. a window moved to the last workspace together with a switch: the add waits for the switch
#      to settle;
#   5. an empty workspace stays while it is shown, and goes once it is left;
#   6. a window on every desktop or kept out of the pager does not hold its workspace, and closing
#      a window removes its workspace a second after the close;
#   7. the Fusion setup run again while the script is on creates no workspace;
#   8. KeepFirst keeps the first workspaces, even empty;
#   9. a name of the user's (or the setup's) is never changed;
#  10. a disable/enable cycle: the unloaded instance changes nothing more and leaves no errors from
#      its handlers; the new instance works.
# Every add and remove is logged by the script with the time since the last switch and close.
# Run: tools/vsession/remote.sh dws-1 packages/kwin/tests/vsession/scenario-workspaces.sh SEED 1440x900 420
exec 2>&1
export OUT
set -euo pipefail
set -x
CHK=$OUT/checks.txt
KLOG=$OUT/kwin.log
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
# A step that fails stops the scenario (strict mode); the reason lands in the checks, so a stopped
# run never reads as a clean one.
trap 'fail "the scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }

# The workspaces as "name|name|..." in KWin's order, and the shown one's name.
desks() {
  K run "var d = workspace.desktops, o = []; for (var i = 0; i < d.length; ++i) { o.push(String(d[i].name)); } report(o.join('|'));" |
    python3 -c 'import json, sys; print(json.load(sys.stdin))'
}
shown() {
  K run "report(String(workspace.currentDesktop.name));" | python3 -c 'import json, sys; print(json.load(sys.stdin))'
}
# What KWin tells D-Bus clients (the workspace dots and the pager read it): the count.
dbus_count() {
  qdbus org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.count
}

# The newest normal window whose class contains CLASS, to workspace INDEX (0-based); no switch.
# A workspace that is not there (a red run can lack it) is reported, never passed on: KWin 6.7.5
# crashes when a script sets a window's desktops to a list holding an undefined desktop.
move_to() { # CLASS INDEX
  K run "var l = workspace.windowList(), w = null, d = workspace.desktops[$2];
    for (var i = 0; i < l.length; ++i) { var c = l[i]; if (c.normalWindow && String(c.resourceClass).indexOf('$1') >= 0) { w = c; } }
    if (w && d) { w.desktops = [d]; }
    report(w && d ? String(w.resourceClass) : 'no window or no workspace $2');" >>"$OUT/move.log"
}
# Show workspace INDEX (when it is there).
switch_to() { # INDEX
  K run "var d = workspace.desktops[$1]; if (d) { workspace.currentDesktop = d; } report(d ? String(d.name) : 'no workspace $1');" >>"$OUT/switch.log"
}
# "Window to Next Desktop" as KWin's shortcut does it: the window and the view move together.
move_with_switch() { # CLASS INDEX
  K run "var l = workspace.windowList(), w = null, d = workspace.desktops[$2];
    for (var i = 0; i < l.length; ++i) { var c = l[i]; if (c.normalWindow && String(c.resourceClass).indexOf('$1') >= 0) { w = c; } }
    if (w && d) { w.desktops = [d]; workspace.currentDesktop = d; workspace.activeWindow = w; }
    report(w && d ? String(w.resourceClass) : 'no window or no workspace $2');" >>"$OUT/move.log"
}
set_flag() { # CLASS PROPERTY VALUE (onAllDesktops, skipPager)
  K run "var l = workspace.windowList(), n = 0;
    for (var i = 0; i < l.length; ++i) { var c = l[i]; if (c.normalWindow && String(c.resourceClass).indexOf('$1') >= 0) { c.$2 = $3; ++n; } }
    report(n);" >>"$OUT/flags.log"
}
close_class() { # CLASS
  K run "var l = workspace.windowList(), n = 0;
    for (var i = 0; i < l.length; ++i) { if (String(l[i].resourceClass).indexOf('$1') >= 0) { l[i].closeWindow(); ++n; } }
    report(n);" >>"$OUT/close.log"
}

# The workspaces become WANT within SECONDS (polled): PASS with the time it took, else FAIL.
wait_desks() { # WANT SECONDS LABEL
  local start got
  start=$(date +%s%N)
  while :; do
    got=$(desks)
    if [ "$got" = "$1" ]; then
      pass "$3: $got after $(( ($(date +%s%N) - start) / 1000000 )) ms"
      return 0
    fi
    if [ $(( ($(date +%s%N) - start) / 1000000000 )) -ge "$2" ]; then
      fail "$3: $got after ${2} s, wanted $1"
      return 0
    fi
    sleep 0.3
  done
}
# The workspaces stay WANT for SECONDS (sampled).
hold_desks() { # WANT SECONDS LABEL
  local end got
  end=$(( $(date +%s) + $2 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    got=$(desks)
    if [ "$got" != "$1" ]; then
      fail "$3: became $got, wanted $1 to stay"
      return 0
    fi
    sleep 0.5
  done
  pass "$3: $1 for $2 s"
}
# The newest script log line matching PATTERN reports at least MIN ms after the last switch.
logged_after_switch() { # PATTERN MIN LABEL
  local line ms
  line=$(grep -a "plasmafusion-workspaces: $1" "$KLOG" | tail -1 || true)
  ms=$(printf '%s' "$line" | sed -n 's/.*(\([0-9]*\) ms after the last switch.*/\1/p')
  if [ -n "$ms" ] && [ "$ms" -ge "$2" ]; then
    pass "$3: $ms ms after the switch"
  else
    fail "$3: '${line:-no log line}'"
  fi
}
# The same for the time since the last close of a window that held its workspace.
logged_after_close() { # PATTERN MIN LABEL
  local line ms
  line=$(grep -a "plasmafusion-workspaces: $1" "$KLOG" | tail -1 || true)
  ms=$(printf '%s' "$line" | sed -n 's/.*, \([0-9]*\) ms after the last close).*/\1/p')
  if [ -n "$ms" ] && [ "$ms" -ge "$2" ]; then
    pass "$3: $ms ms after the close"
  else
    fail "$3: '${line:-no log line}'"
  fi
}
script_errors() { grep -a 'plasmafusion-workspaces' "$KLOG" | grep -acE 'Error|error:' || true; }
enable() { # true|false
  kwriteconfig6 --file kwinrc --group Plugins --key plasmafusion-workspacesEnabled "$1"
  qdbus org.kde.KWin /KWin reconfigure
  sleep 2
}

# ---- the Fusion setup as a user has it before turning the dynamic workspaces on
fc_rc=0
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || fc_rc=$?
info "fusion-config rc=$fc_rc"
sleep 3
wait_desks "Work|Design|Media|Chat" 10 "the setup's four named workspaces"
switch_to 0
kwrite >/dev/null 2>&1 &
sleep 4
info "workspaces before: $(desks), shown: $(shown)"
shot 00-setup

# ---- 1. turned on: the start grace, then the empty ones go
kwriteconfig6 --file kwinrc --group Script-plasmafusion-workspaces --key KeepFirst 0
enable true
loaded=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-workspaces)
[ "$loaded" = true ] && pass "the dynamic workspaces script is loaded" || fail "the script is not loaded ($loaded)"
grep -a 'plasmafusion-workspaces' "$KLOG" | tail -2 >>"$CHK" 2>/dev/null || true
errors_start=$(script_errors)
hold_desks "Work|Design|Media|Chat" 5 "nothing is removed right after the start (session restore)"
wait_desks "Work|Design" 12 "after the start grace the empty ones go but the one after the last occupied"
[ "$(dbus_count)" = 2 ] && pass "KWin's D-Bus (the dots and the pager) reports 2" || fail "KWin's D-Bus reports $(dbus_count)"
shot 10-started

# ---- 2. a window moved to the last workspace (no switch): the next empty one comes at once
move_to kwrite 1
wait_desks "Work|Design|Workspace 3" 2 "a window on the last workspace adds an empty one, named for its position"
shot 20-added

# ---- 3. following the window: the empty first workspace goes after the slide, names follow
switch_to 1
got=$(desks)
[ "$got" = "Work|Design|Workspace 3" ] && pass "right after the switch nothing changed yet ($got)" ||
  fail "right after the switch the workspaces changed already: $got"
wait_desks "Design|Workspace 2" 4 "the empty first workspace went and the numbered name followed its position"
logged_after_switch "removed empty workspace \"Work\"" 1000 "the removal waited for the switch to settle"
shot 30-renumbered

# ---- 4. "window to next desktop" at the end: the add waits for the switch to settle
konsole >/dev/null 2>&1 &
sleep 4
move_with_switch konsole 1
got=$(desks)
[ "$got" = "Design|Workspace 2" ] && pass "right after the move with a switch no workspace was added yet" ||
  fail "a workspace was added during the switch: $got"
wait_desks "Design|Workspace 2|Workspace 3" 4 "the next empty workspace came after the switch settled"
logged_after_switch "added workspace \"Workspace 3\"" 1000 "the add waited for the switch to settle"

# ---- 5. an empty workspace stays while shown: Design kwrite, Workspace 2 konsole, then a third app
kcalc >/dev/null 2>&1 &
sleep 4
move_to kcalc 2
wait_desks "Design|Workspace 2|Workspace 3|Workspace 4" 3 "a third window on the last workspace"
close_class konsole
sleep 1
hold_desks "Design|Workspace 2|Workspace 3|Workspace 4" 4 "the shown workspace stays while empty"
switch_to 2
wait_desks "Design|Workspace 2|Workspace 3" 5 "left, the empty workspace goes (and the names follow)"
[ "$(shown)" = "Workspace 2" ] && pass "the view stayed with the window (kcalc's workspace, now Workspace 2)" ||
  fail "the view is on $(shown)"
shot 50-left

# ---- 6. windows that do not hold a workspace. The view goes back to Design (kwrite), so kcalc's
# workspace is neither shown nor protected by anything but the window itself.
switch_to 0
sleep 2
set_flag kcalc onAllDesktops true
wait_desks "Design|Workspace 2" 4 "a window on every desktop does not hold its workspace"
set_flag kcalc onAllDesktops false
move_to kcalc 1
wait_desks "Design|Workspace 2|Workspace 3" 3 "back on one workspace it holds it again"
set_flag kcalc skipPager true
wait_desks "Design|Workspace 2" 4 "a window kept out of the pager does not hold its workspace"
set_flag kcalc skipPager false
wait_desks "Design|Workspace 2|Workspace 3" 3 "back in the pager it holds it again"
# Closing it: its workspace stays as the empty one at the end, the one after goes - a second after
# the close (a dialog may be handing over to its app's next window).
close_class kcalc
wait_desks "Design|Workspace 2" 5 "closed, the extra empty workspace goes"
logged_after_close "removed empty workspace \"Workspace 3\"" 1000 "the removal waited a second after the close"
sleep 1

# ---- 7. the Fusion setup again, with the script on: no workspace created
before=$(desks)
fc2_rc=0
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc2.log" 2>&1 || fc2_rc=$?
info "fusion-config (dynamic on) rc=$fc2_rc; workspaces before $before"
if grep -q 'not created (dynamic workspaces are on' "$OUT/fc2.log" && ! grep -q '  create workspace' "$OUT/fc2.log"; then
  pass "the setup creates no workspace while the dynamic workspaces are on"
else
  fail "the setup created workspaces: $(grep -a 'workspace' "$OUT/fc2.log" | tr '\n' ' ')"
fi
info "setup lines: $(grep -a 'workspace' "$OUT/fc2.log" | tr '\n' ' ')"
sleep 3
after=$(desks)
case $after in Work\|*) pass "the setup named the first workspace as it does (Work); the rest follow the windows: $after" ;;
  *) fail "after the setup: $after" ;; esac
switch_to 0
sleep 2

# ---- 8. KeepFirst: a workspace the user adds empty goes again, unless KeepFirst keeps it
qdbus org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.createDesktop 2 Extra >/dev/null
first=$(desks)
info "after adding Extra: $first"
wait_desks "$after" 4 "an empty workspace the user adds goes again (KeepFirst 0)"
kwriteconfig6 --file kwinrc --group Script-plasmafusion-workspaces --key KeepFirst 3
qdbus org.kde.KWin /KWin reconfigure
sleep 2
qdbus org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.createDesktop 2 Extra >/dev/null
sleep 1
kept=$(desks)
hold_desks "$kept" 4 "KeepFirst 3 keeps the first three, even empty"
case $kept in *\|Extra\|*|*\|Extra) pass "the added workspace is among them: $kept" ;; *) fail "Extra is not kept: $kept" ;; esac
kwriteconfig6 --file kwinrc --group Script-plasmafusion-workspaces --key KeepFirst 0
qdbus org.kde.KWin /KWin reconfigure
sleep 4
case $(desks) in *Extra*) fail "KeepFirst 0 again: Extra stayed ($(desks))" ;; *) pass "KeepFirst 0 again: the empty Extra went ($(desks))" ;; esac

# ---- 9. a name of the user's stays (the setup's Design stayed through the removal in 3; the
# script renames only its own "Workspace N" names)
switch_to 0
sleep 2
info "before the rename: $(desks)"
id=$(K run "var d = workspace.desktops; report(String(d[d.length - 1].id));" | python3 -c 'import json, sys; print(json.load(sys.stdin))')
qdbus org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.setDesktopName "$id" Notes >/dev/null
sleep 2
case $(desks) in *\|Notes) pass "a name the user gives the empty last workspace stays: $(desks)" ;; *) fail "the user's name changed: $(desks)" ;; esac
shot 90-names

# ---- 10. disable/enable: the old instance stops, leaves no errors, the new one works
kwrite >/dev/null 2>&1 &
sleep 4
enable false
loaded=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-workspaces)
[ "$loaded" = false ] && pass "disabled: the script is unloaded" || fail "disabled: the script is still loaded ($loaded)"
off_before=$(desks)
count_before=$(echo "$off_before" | tr '|' '\n' | wc -l)
move_to kwrite $(( count_before - 1 ))
sleep 3
hold_desks "$off_before" 3 "disabled: a window on the last workspace adds nothing"
enable true
loaded=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-workspaces)
[ "$loaded" = true ] && pass "enabled again: the script is loaded" || fail "enabled again: the script is not loaded ($loaded)"
grown=$(desks)
[ "$(echo "$grown" | tr '|' '\n' | wc -l)" = $(( count_before + 1 )) ] && pass "enabled again: the empty one at the end is added ($grown)" ||
  fail "enabled again: $grown (had $off_before)"
errors_end=$(script_errors)
[ "$errors_end" = "$errors_start" ] && pass "no errors from the script's handlers ($errors_end before and after the cycle)" ||
  fail "the script's handlers raised errors ($errors_start at the start, $errors_end at the end)"
grep -a 'plasmafusion-workspaces' "$KLOG" | grep -aE 'Error|error:' | tail -4 >>"$CHK" || true
shot 99-end

info "kwinrc [Desktops]: $(kreadconfig6 --file kwinrc --group Desktops --key Number) workspace(s)"
info "script log lines:"; grep -a 'plasmafusion-workspaces' "$KLOG" | tail -30 >>"$CHK" 2>/dev/null || true
# The verdict: every check runs (a red run lists each failing behaviour), and the scenario's own
# status says whether any failed - the session log keeps it as "scenario rc". remote.sh's status
# stays what its header says (the session ran and the results were fetched).
failed=$(grep -c '^FAIL' "$CHK" || true)
info "verdict: $(grep -c '^PASS' "$CHK" || true) passed, $failed failed"
info "done"
trap - ERR
set +e
[ "$failed" = 0 ]
