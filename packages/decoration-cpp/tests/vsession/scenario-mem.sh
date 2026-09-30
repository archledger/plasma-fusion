# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Virtual-session scenario (test tooling): KWin's memory per decorated window (BACKLOG C10: at
# most 5 MiB of anonymous memory per extra window). MEMDECO in the seed's params.sh picks the
# decoration (cpp = this plugin, aurorae = the phase-1 Plasma Fusion Aurorae theme, breeze):
#
#   SEED_PARAMS=MEMDECO=aurorae make-seed.sh ... ; tools/vsession/remote.sh o1dc-N scenario-mem.sh SEED 1920x1200 600
#
# Opens KWrite windows one by one (all 800x500, cascaded, so every decoration is the same size),
# and after 0, 1, 5, 10 and 15 windows writes KWin's /proc status memory lines (RssAnon = the
# anonymous memory) and, through sudo -n when available, its smaps_rollup totals to mem.txt.
# One decoration per session: freed memory stays in KWin's heap, so a second run in the same KWin
# would look cheaper.
. "$HOME/pf-deco/params.sh"
# shellcheck source=lib.sh
. "$HOME/pf-deco/lib.sh"
AWAY='move 1420 880'
MEMDECO=${MEMDECO:-cpp}

measure() { # LABEL WINDOWS
  local kp
  pfinput "$AWAY" 'sleep 0.2'
  sleep 5
  kp=$(kwin_pid) || { log "ERROR: no KWin pid"; return; }
  {
    printf 'deco=%s windows=%s label=%s pid=%s ' "$MEMDECO" "$2" "$1" "$kp"
    awk '/^(RssAnon|RssFile|RssShmem|VmRSS):/ {printf "%s=%s ", $1, $2}' "/proc/$kp/status"
    # smaps_rollup needs ptrace access (KWin is not dumpable): read-only, through sudo when it
    # needs no password, else skipped
    sudo -n cat "/proc/$kp/smaps_rollup" 2>/dev/null | awk '/^(Rss|Pss|Pss_Anon|Pss_File|Pss_Shmem|Anonymous|Private_Dirty):/ {printf "smaps_%s=%s ", $1, $2}'

    echo
  } >>"$OUT/mem.txt"
  log "measured $1 ($2 windows)"
}

open_to() { # N: open KWrite windows until N are there, then cascade them at 800x500
  local have tries=0
  have=$(kwrite_windows)
  while [ "$have" -lt "$1" ] && [ "$tries" -lt $(($1 * 2 + 4)) ]; do
    kwrite >>"$OUT/kwrite.log" 2>&1 &
    sleep 2.5
    have=$(kwrite_windows)
    tries=$((tries + 1))
  done
  [ "$have" -ge "$1" ] || log "ERROR: only $have KWrite windows (wanted $1)"
  kwinjs <<'JS'
let i = 0;
for (const w of workspace.windowList()) {
  if (!w.normalWindow || (w.resourceClass || "").indexOf("kwrite") < 0) { continue; }
  w.setMaximize(false, false);
  w.frameGeometry = {x: 60 + 30 * (i % 15), y: 60 + 20 * (i % 15), width: 800, height: 500};
  i++;
}
JS
  sleep 1
}

kwrite_windows() { # number of KWrite windows KWin manages (read back from kwin.log)
  local token=$RANDOM$RANDOM
  kwinjs <<JS
console.warn("PFCXCOUNT $token " + workspace.windowList().filter(w => w.normalWindow && (w.resourceClass || "").indexOf("kwrite") >= 0).length);
JS
  sleep 0.3
  grep -o "PFCXCOUNT $token [0-9]*" "$OUT/kwin.log" | tail -1 | awk '{print $3}' | grep . || echo 0
}

date "+%Y-%m-%d %H:%M:%S" >"$OUT/start.txt"
fusion_desktop
setdeco RightGlyphs default
use_decoration "$MEMDECO"
measure start 0
for n in 1 5 10 15; do
  open_to "$n"
  geom "windows-$n"
  measure "windows-$n" "$n"
done
[ "$MEMDECO" = cpp ] && check_plugin
shot 01-windows
log "done"
