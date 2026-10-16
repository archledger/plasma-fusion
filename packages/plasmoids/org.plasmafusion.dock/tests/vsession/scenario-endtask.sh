# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# The dock's End Task in a private session (real plasmashell and KWin): the Fusion setup with the
# stage in ~/pf-stage and tools/ in ~/pf-tools, then a stand-in app that ignores SIGTERM (kdialog
# started with SIGTERM ignored), driven through the dock's test hook (debugAction: menu, pick):
#   1. the running app's menu has End Task…; a pinned app that is not running has none;
#   2. End Task… asks first (End Task, Cancel), and Cancel leaves the app running; an End Task…
#      that comes after a task before the stand-in's went (kcalc, started first, quit), when the
#      menu's row is another app's or none, asks nothing;
#   3. End Task ends it: SIGTERM, which it ignores, then SIGKILL.
# Run: tools/vsession/remote.sh dock-endtask packages/plasmoids/org.plasmafusion.dock/tests/vsession/scenario-endtask.sh SEED 1440x900 240
export OUT
set -euo pipefail
set -x
CHK=$OUT/checks.txt
PLOG=$OUT/plasmashell.log
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
# A step that fails stops the scenario (strict mode); the reason lands in the checks.
trap 'fail "the scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
mark() { MARK=$(wc -l <"$PLOG"); }
MARK=0
wait_log() { # PATTERN SECONDS: a line matching PATTERN logged after the last mark
  local i
  for ((i = 0; i < $2 * 4; i++)); do
    tail -n +"$((MARK + 1))" "$PLOG" | grep -aqE "$1" && return 0
    sleep 0.25
  done
  return 1
}
since() { tail -n +"$((MARK + 1))" "$PLOG" | grep -aE "$1" | tail -1; }
dock() { # the dock's debugAction
  evaljs - >/dev/null 2>>"$OUT/errors.log" <<JS
panels().forEach(function (p) { p.widgets("org.plasmafusion.dock").forEach(function (w) { w.currentConfigGroup = ["General"]; w.writeConfig("debugAction", "$1"); }); });
JS
}
alive() { [ -d "/proc/$1" ] && [ "$(sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -c1)" != Z ]; }

fc=0
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || fc=$?
info "fusion-config rc=$fc"
[ "$fc" = 0 ]
pfv_restart_shell 12

# An app that is not pinned, started first, so its task comes before the stand-in's (step 2).
kcalc >"$OUT/kcalc.log" 2>&1 &
calc=$!
sleep 3
# The stand-in: kdialog with SIGTERM ignored (an ignored signal stays ignored across exec).
sh -c "trap '' TERM; exec kdialog --title 'Stuck app' --msgbox 'A stand-in that ignores SIGTERM'" >"$OUT/kdialog.log" 2>&1 &
app=$!
sleep 4
# ROW of the dock's task whose id matches PATTERN, from a fresh targets report (empty: none).
task_row() {
  mark
  dock dump-targets
  wait_log "dock: targets" 5
  tr ' ' '\n' <<<"$(since "dock: targets")" | { grep -m1 -o "task[0-9]*-[^@]*$1" || true; } | sed 's/^task\([0-9]*\)-.*/\1/'
}
calcrow=$(task_row kcalc)
mark
dock dump-targets
wait_log "dock: targets" 5
targets=$(since "dock: targets")
row=$(tr ' ' '\n' <<<"$targets" | grep -m1 -o 'task[0-9]*-[^@]*kdialog' | sed 's/^task\([0-9]*\)-.*/\1/')
# Dolphin is pinned by default; without it the check of a pinned app is skipped.
idle=$(tr ' ' '\n' <<<"$targets" | grep -m1 -o 'task[0-9]*-org.kde.dolphin' | sed 's/^task\([0-9]*\)-.*/\1/' || true)
info "stand-in pid $app, dock row ${row:-none}; kcalc row ${calcrow:-none}; Dolphin (pinned, not running) row ${idle:-none}"

# ---- 1. the menus
mark
dock "menu:$row"
if wait_log "dock: menu [^:]*kdialog: .*End Task…" 5; then pass "1: the running app's menu has End Task… ($(since 'dock: menu' | sed 's/.*: //'))"
else fail "1: no End Task… for the running app ($(since 'dock: menu'))"; fi
shot 10-menu
dock close-menu
sleep 0.5
if [ -n "${idle:-}" ]; then
  mark
  dock "menu:$idle"
  wait_log "dock: menu " 5
  case "$(since 'dock: menu ')" in
    *"End Task"*) fail "1: a pinned app that is not running offers End Task ($(since 'dock: menu '))" ;;
    *) pass "1: a pinned app that is not running has no End Task" ;;
  esac
  dock close-menu
  sleep 0.5
fi

# ---- 2. the confirmation, then Cancel
mark
dock "menu:$row"
wait_log "dock: menu " 5
mark
dock "pick:End Task…"
if wait_log "dock: menu [^:]*kdialog: End Task \| Cancel" 5; then pass "2: End Task… asks first (End Task, Cancel)"; else fail "2: no confirmation ($(since 'dock: pick'))"; fi
shot 20-confirm
dock "pick:Cancel"
sleep 4
if alive "$app"; then pass "2: Cancel leaves the app running"; else fail "2: the app is gone after Cancel"; fi
# An End Task… whose row changed before it ran: the stand-in's menu, then the task before it goes.
if [ -n "${calcrow:-}" ] && [ "$calcrow" -lt "$row" ]; then
  mark
  dock "menu:$row"
  wait_log "dock: menu " 5
  kill "$calc"
  for _ in $(seq 1 20); do [ "$(task_row kdialog)" = "$row" ] || break; sleep 0.5; done
  mark
  dock "pick:End Task…"
  if wait_log "dock: end task [^ ]*kdialog: its row changed, not asked" 5 && ! since "dock: menu [^:]*: End Task" >/dev/null; then
    pass "2: End Task… after the task before it went asks nothing ($(since 'dock: end task'))"
  else
    fail "2: a stale End Task…: $(since 'dock: end task') $(since 'dock: menu')"
  fi
  row=$(task_row kdialog)
  info "the stand-in's row now ${row:-none}"
else
  fail "2: kcalc's task (row ${calcrow:-none}) is not before the stand-in's ($row): no stale End Task to try"
fi

# ---- 3. End Task
mark
dock "menu:$row"
wait_log "dock: menu " 5
dock "pick:End Task…"
wait_log "dock: menu [^:]*kdialog: End Task" 5
dock "pick:End Task"
wait_log "dock: end task " 5
info "$(since 'dock: end task ')"
for _ in $(seq 1 40); do alive "$app" || break; sleep 0.25; done
if alive "$app"; then fail "3: the app still runs 10 s after End Task"
else pass "3: End Task ends the app that ignores SIGTERM ($(since 'dock: end task ' | sed 's/.*dock: //'))"; fi
shot 30-ended
info "done"
# A failed check fails the scenario (scenario rc), as the KWin scenarios do.
trap - ERR
set +e
[ "$(grep -c '^FAIL' "$CHK" || true)" = 0 ]
