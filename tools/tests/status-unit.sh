#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of `plasma-fusion status`' profile and capability lines (ADR 0001), the command as it
# is, against stand-ins for kwin_wayland, busctl (KWin's support information, its scripting
# interface) and journalctl (where the probe's answer is read), with a throw-away package tree:
#   1. outside a session: the stock profile, and where to run the command to see the capabilities;
#   2. stock KWin: none of the fork's capabilities, the probe loaded, run and unloaded, its file gone;
#   3. the fork without the metapackage: the three capabilities and the note that says so;
#   4. the full profile: the pin and the fork tag from the metapackage's record;
#   5. the full profile with the session still on the KWin from before: the note to log in again;
#   6. the full profile under another Plasma: the note that names both versions;
#   7. an answer that never reaches the journal: said, and the support information still read;
#   8. no KWin on the session bus: as outside a session;
#   9. the probe KWin is given reads the properties and the function ADR 0001 names;
#  10. every call's probe is found by the compositor: KWin's QML loader keeps the listing of a
#      directory it has read for as long as it runs, and a file made there later does not exist
#      for it (the stand-in keeps the same list).
# Test tooling only, not installed.
#
#   status-unit.sh BASE
#
# BASE must be a scratch directory on disk (not /tmp); it is emptied first.
set -euo pipefail
BASE=${1:?scratch directory}
BASE=$(realpath -m -- "$BASE")
case $BASE in /tmp/* | /tmp) echo "use a directory on disk, not /tmp" >&2; exit 2 ;; esac
TOP=$(cd "$(dirname "$0")/../.." && pwd)
CLI=$TOP/tools/plasma-fusion
[ -f "$CLI" ] || { echo "FAIL: $CLI is missing"; exit 1; }
rm -rf "${BASE:?}"
mkdir -p "$BASE"

PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
has() { # NAME TEXT: the last output has the line (or part of one)
  if grep -qF -- "$2" <<<"$OUT"; then ok "$1"; else bad "$1 (no '$2' in the output)"; fi
}
hasnot() {
  if grep -qF -- "$2" <<<"$OUT"; then bad "$1 ('$2' in the output)"; else ok "$1"; fi
}

# The package: a data directory with the version and nothing compiled.
export T=$BASE/t HOME=$BASE/home
SHARE=$BASE/share
mkdir -p "$T" "$HOME" "$SHARE/plasma-fusion" "$BASE/run" "$BASE/root"
echo 0.0.0-test >"$SHARE/plasma-fusion/version"
echo 6.8 >"$SHARE/plasma-fusion/tested-plasma.txt"
export XDG_DATA_DIRS=$SHARE XDG_DATA_HOME=$HOME/.local/share XDG_STATE_HOME=$HOME/.local/state
export XDG_RUNTIME_DIR=$BASE/run PF_GREETER_ROOT=$BASE/root

# The stand-ins, first in PATH. $T/mode says which compositor answers: stock, fork, silent
# (the fork, its probe's answer never written) or absent (no KWin on the bus). $T/kwin is the
# version kwin_wayland reports.
BIN=$BASE/bin
mkdir -p "$BIN"
cat >"$BIN/kwin_wayland" <<'EOF'
#!/bin/bash
echo "kwin $(cat "$T/kwin")"
EOF
cat >"$BIN/journalctl" <<'EOF'
#!/bin/bash
cat "$T/journal" 2>/dev/null
EOF
cat >"$BIN/busctl" <<'EOF'
#!/bin/bash
mode=$(cat "$T/mode")
printf '%s\n' "$*" >>"$T/busctl.calls"
case "$*" in
  *NameHasOwner*)
    if [ "$mode" = absent ]; then echo "b false"; else echo "b true"; fi ;;
  *supportInformation*)
    if [ "$mode" = stock ]; then
      printf 's "KWin Support Information:\\nLoaded Effects:\\noverview:\\nlayout: 1\\n"\n'
    else
      printf 's "KWin Support Information:\\nLoaded Effects:\\noverview:\\nlayout: 1\\nplasmaFusionOffscreenOpacityVersion: 1\\n"\n'
    fi ;;
  *loadDeclarativeScript*)
    # ... loadDeclarativeScript ss FILE NAME
    file=${*: -2:1} name=${*: -1}
    cp "$file" "$T/probe.qml"
    echo "$name" >"$T/nonce"
    # Qt's QML loader reads a directory once and keeps what it found (QQmlTypeLoader's
    # directory cache): a file made later in a directory it has read fails to load ("File name
    # case mismatch"), and the script it would have been says nothing.
    dir=$(dirname "$file")
    if grep -qxF -- "$dir" "$T/read-directories" 2>/dev/null; then
      echo stale >"$T/load"
    else
      echo "$dir" >>"$T/read-directories"
      echo fresh >"$T/load"
    fi
    echo "i 7" ;;
  */Scripting/Script7*run*)
    nonce=$(cat "$T/nonce")
    [ "$(cat "$T/load")" = fresh ] || exit 0
    case $mode in
      stock) echo "qml: plasma-fusion-probe $nonce thumbnail=0 tiling=0" >>"$T/journal" ;;
      fork) echo "qml: plasma-fusion-probe $nonce thumbnail=1 tiling=1" >>"$T/journal" ;;
    esac ;;
  *unloadScript*)
    echo "${*: -1}" >>"$T/unloaded" ;;
esac
EOF
chmod +x "$BIN/kwin_wayland" "$BIN/journalctl" "$BIN/busctl"
export PATH=$BIN:$PATH

run() { # MODE [KWIN VERSION]: the command's output in OUT
  echo "$1" >"$T/mode"
  echo "${2:-6.8.2}" >"$T/kwin"
  rm -f "$T/journal" "$T/busctl.calls" "$T/unloaded" "$T/nonce" "$T/probe.qml"
  OUT=$(bash "$CLI" status 2>&1) || { bad "status exits 0 ($1)"; OUT=; }
}
record() { # the metapackage's record, or none
  if [ "${1:-}" = none ]; then
    rm -f "$SHARE/plasma-fusion/full-profile"
  else
    printf 'kwin=%s\ntag=%s\n' 6.8.2-3.fc44.pf3 v6.8.2-pf3 >"$SHARE/plasma-fusion/full-profile"
  fi
}

# 1. outside a session
record none
unset DBUS_SESSION_BUS_ADDRESS
run fork
has "1 the stock profile" "  profile: stock (the distribution's KWin)"
has "1 where the capabilities can be seen" "the running KWin's capabilities: run this in a terminal inside your Plasma session"
if [ -e "$T/busctl.calls" ]; then bad "1 nothing is asked of a bus outside a session"; else ok "1 nothing is asked of a bus outside a session"; fi

export DBUS_SESSION_BUS_ADDRESS=unix:path=$BASE/run/bus

# 2. stock KWin
run stock
has "2 the stock profile" "  profile: stock (the distribution's KWin)"
has "2 none of the fork's capabilities" "the running KWin's capabilities: none of the fork's (every feature uses its stock fallback)"
hasnot "2 no note" "note: this KWin advertises"
if [ "$(cat "$T/unloaded" 2>/dev/null)" = "$(cat "$T/nonce" 2>/dev/null)" ] && [ -s "$T/nonce" ]; then
  ok "2 the probe is unloaded again"
else
  bad "2 the probe is unloaded again"
fi
if compgen -G "$XDG_RUNTIME_DIR/plasma-fusion-probe-*" >/dev/null; then bad "2 the probe's file is gone"; else ok "2 the probe's file is gone"; fi

# 3. the fork, installed by hand
run fork
has "3 the stock profile" "  profile: stock (the distribution's KWin)"
has "3 the thumbnail lifecycle" "    thumbnail source lifecycle: version 1"
has "3 offscreen opacity" "    offscreen opacity: version 1"
has "3 the tiling facade" "    transient tiling (dynamic tiling): yes"
has "3 the fork without the profile is named" "note: this KWin advertises the fork's capabilities without the full profile"

# 4. the full profile
record
run fork
has "4 the full profile with its pin and tag" "  profile: full (the maintained KWin fork, pinned at 6.8.2-3.fc44.pf3, fork tag v6.8.2-pf3)"
has "4 the capabilities" "    transient tiling (dynamic tiling): yes"
hasnot "4 no note about a fork by hand" "without the full profile"
hasnot "4 no note about another Plasma" "the full profile pins KWin"
hasnot "4 no note to log in again" "log out and in"

# 5. the full profile, the session still on the KWin from before
run stock
has "5 the full profile" "  profile: full (the maintained KWin fork, pinned at 6.8.2-3.fc44.pf3, fork tag v6.8.2-pf3)"
has "5 none advertised" "the running KWin's capabilities: none of the fork's"
has "5 the note to log in again" "log out and in (the session still runs the KWin from before the profile)"

# 6. the full profile under another Plasma
run fork 6.9.0
has "6 both versions are named" "note: the full profile pins KWin 6.8.2 and the running KWin is 6.9.0"
has "6 the way back" "install.sh --full-restore"

# 7. the probe's answer never reaches the journal
run silent
has "7 the thumbnail lifecycle could not be asked" "    thumbnail source lifecycle: could not be asked"
has "7 the tiling facade could not be asked" "    transient tiling (dynamic tiling): could not be asked"
has "7 the support information is still read" "    offscreen opacity: version 1"
hasnot "7 no note on an incomplete answer" "log out and in"

# 8. no KWin on the session bus
record none
run absent
has "8 as outside a session" "the running KWin's capabilities: run this in a terminal inside your Plasma session"

# 9. the probe
run fork
for word in 'import org.kde.kwin' WindowThumbnail plasmaFusionThumbnailSourceLifecycleVersion 'Workspace.transientTiling' "plasma-fusion-probe $(cat "$T/nonce")"; do
  if grep -qF -- "$word" "$T/probe.qml"; then ok "9 the probe has '$word'"; else bad "9 the probe has '$word'"; fi
done
if grep -qF 'supportInformation' "$T/busctl.calls"; then ok "9 the support information is asked"; else bad "9 the support information is asked"; fi

# 10. one compositor, several calls
run fork
has "10 a second call's probe is found" "    thumbnail source lifecycle: version 1"
run fork
has "10 a third call's probe is found" "    transient tiling (dynamic tiling): yes"
if [ "$(sort "$T/read-directories" | uniq -d | wc -l)" -eq 0 ] && [ "$(wc -l <"$T/read-directories")" -ge 8 ]; then
  ok "10 every probe had a directory of its own"
else
  bad "10 every probe had a directory of its own"
fi

echo "status-unit: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
