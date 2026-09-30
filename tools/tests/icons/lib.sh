# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Shared part of the icon-position scenarios (sourced inside a tools/vsession session after
# vsession.sh's own helpers). The seed HOME holds the tools tree at ~/pf-tools and the built
# Plasma Fusion HOME tree at ~/pf-stage.
# shellcheck shell=bash

export PFV_T0=${PFV_T0:-$(date +%s)}
export OUT
TESTS=$HOME/pf-tools/tests
icons() { python3 "$TESTS/icons/icons.py" "$@"; }
pfkwin() { python3 "$TESTS/lib/pfkwin.py" "$@"; }
log() { echo "[$(date +%T)] $*"; echo "[$(date +%T)] $*" >>"$OUT/steps.log"; }

# check STEP: compare with the baseline and take a screenshot
check() {
  log "check $1"
  icons check "$1" >>"$OUT/steps.log" 2>&1 || log "check $1: FAIL"
  shot "$1"
}

# First output's name (Virtual-0 on the virtual backend) and all names.
outputs() { kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '/^Output:/{print $3}' | sort; }

# kscreen OUTPUT.SETTING...: apply with kscreen-doctor, log the result, let Plasma settle.
kscreen() {
  log "kscreen-doctor $*"
  kscreen-doctor "$@" >>"$OUT/kscreen.log" 2>&1 || log "kscreen-doctor $* failed"
  sleep "${SETTLE:-6}"
}

# Panel id of the dock (the bottom panel).
dock_id() {
  evaljs - <<'JS'
var ps = panels(), id = -1;
for (var i = 0; i < ps.length; ++i) if (ps[i].location === "bottom") id = ps[i].id;
print(id);
JS
}
