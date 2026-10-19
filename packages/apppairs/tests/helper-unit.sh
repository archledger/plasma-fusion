#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of plasma-fusion-app-pair (saved app pairs), the helper as it is, against stand-ins for
# busctl (plasmashell's desktop scripting: each call's script kept) and kbuildsycoca6 (counted),
# with a throw-away HOME and XDG data directories holding the apps' desktop files:
#   1. save: the pair's entry (hidden, the apps, the split snapped to 1/3, 1/2 or 2/3, both names,
#      its Exec), the cache rebuilt before the home screen is asked to pin it;
#   2. the same two apps again: the same entry with the new split; reversed: another pair;
#   3. swap, open (the dock's pairRequest), remove;
#   4. what it refuses: one app twice, no desktop file id, no split, a path that is not a pair's.
# Test tooling only, not installed.
#
#   helper-unit.sh BASE
#
# BASE must be a scratch directory on disk (not /tmp); it is emptied first.
set -euo pipefail
BASE=${1:?scratch directory}
BASE=$(realpath -m -- "$BASE")
case $BASE in /tmp/* | /tmp) echo "use a directory on disk, not /tmp" >&2; exit 2 ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
HELPER=$HERE/../plasma-fusion-app-pair
[ -f "$HELPER" ] || { echo "FAIL: the helper $HELPER is missing"; exit 1; }
rm -rf "${BASE:?}"
mkdir -p "$BASE"

PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
check() { # NAME CONDITION...
  local name=$1
  shift
  if "$@"; then ok "$name"; else bad "$name"; fi
}

# The stand-ins, first in PATH.
BIN=$BASE/bin
mkdir -p "$BIN"
cat >"$BIN/busctl" <<'EOF'
#!/bin/bash
n=$(( $(cat "$T/calls" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$T/calls"
printf '%s\n' "$@" >"$T/busctl.$n"
# the cache must be rebuilt before the shell is asked anything
cat "$T/sycoca" >"$T/busctl.$n.sycoca" 2>/dev/null || echo 0 >"$T/busctl.$n.sycoca"
EOF
cat >"$BIN/kbuildsycoca6" <<'EOF'
#!/bin/bash
echo $(( $(cat "$T/sycoca" 2>/dev/null || echo 0) + 1 )) >"$T/sycoca"
EOF
chmod +x "$BIN/busctl" "$BIN/kbuildsycoca6"

export T=$BASE/t HOME=$BASE/home
export XDG_DATA_HOME=$HOME/.local/share XDG_DATA_DIRS=$BASE/sys1:$BASE/sys2
export PATH=$BIN:$PATH
mkdir -p "$T" "$XDG_DATA_HOME/applications" "$BASE/sys1/applications" "$BASE/sys2/applications"
app() { # DIR ID NAME
  printf '%s\n' '[Desktop Entry]' Type=Application "Name=$3" "Name[de]=$3 (de)" Exec=true '' \
    '[Desktop Action new]' Name=Other >"$1/applications/$2"
}
app "$BASE/sys1" org.kde.dolphin.desktop Dolphin
app "$BASE/sys2" firefox.desktop Firefox
app "$BASE/sys2" org.kde.kate.desktop "Kate (system)"
app "$XDG_DATA_HOME" org.kde.kate.desktop Kate
APPS=$XDG_DATA_HOME/applications
key() { # FILE KEY: the key of the [Desktop Entry] group
  awk -v k="$2" '/^\[/ { g = $0; next }
    g == "[Desktop Entry]" && index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$1"
}
pairs() { find "$APPS" -name 'org.plasmafusion.pair-*.desktop' | wc -l; }
last_call() { echo "$T/busctl.$(cat "$T/calls")"; }

# ---- 1. save
id=$("$HELPER" save org.kde.dolphin.desktop firefox.desktop 0.47)
f=$APPS/$id
is_pair_id() { [[ $1 =~ ^org\.plasmafusion\.pair-[0-9A-Za-z]+\.desktop$ ]]; }
check "save prints the pair's id ($id)" is_pair_id "$id"
check "save writes the entry" test -f "$f"
check "the left app" test "$(key "$f" X-PlasmaFusion-PairLeft)" = org.kde.dolphin.desktop
check "the right app" test "$(key "$f" X-PlasmaFusion-PairRight)" = firefox.desktop
check "the split snapped to 1/2 (0.47)" test "$(key "$f" X-PlasmaFusion-PairShare)" = 0.5
check "both apps' names (the Desktop Entry's, not an action's)" \
  test "$(key "$f" Name)" = "Dolphin · Firefox"
check "hidden from the app lists" test "$(key "$f" NoDisplay)" = true
check "no launch feedback" test "$(key "$f" StartupNotify)" = false
check "its Exec opens it with this helper" \
  test "$(key "$f" Exec)" = "\"$(realpath "$HELPER")\" open %k"
call=$(last_call)
check "the home screen is asked to pin it" grep -q "pinRequest.*:applications:$id" "$call"
check "only the Plasma Fusion home screen" \
  grep -q 'd.type === "org.plasmafusion.desktop"' "$call"
check "through plasmashell's evaluateScript" test "$(head -n 7 "$call" | tr '\n' ' ')" \
  = "--user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "
check "the cache rebuilt before the home screen is asked" test "$(cat "$call.sycoca")" -ge 1
check "no temporary file left" test "$(find "$APPS" -name '*.desktop.*' | wc -l)" = 0

# ---- 2. the same two apps again; reversed
id2=$("$HELPER" save org.kde.dolphin.desktop firefox.desktop 0.3)
check "the same apps in the same order: the same pair" test "$id2" = "$id"
check "with the new split, 1/3" test "$(key "$f" X-PlasmaFusion-PairShare)" = 0.3333
check "still one pair" test "$(pairs)" = 1
id3=$("$HELPER" save firefox.desktop org.kde.dolphin.desktop 0.7)
check "reversed: another pair" test "$id3" != "$id"
check "split 2/3" test "$(key "$APPS/$id3" X-PlasmaFusion-PairShare)" = 0.6667
check "two pairs" test "$(pairs)" = 2
id4=$("$HELPER" save org.kde.kate.desktop org.kde.unknown.desktop 0.5)
check "the user's own entry of an app first; an app without one: its id" \
  test "$(key "$APPS/$id4" Name)" = "Kate · org.kde.unknown"

# ---- 3. swap, open, remove
"$HELPER" swap "$id"
check "swap: the right app on the left" test "$(key "$f" X-PlasmaFusion-PairLeft)" = firefox.desktop
check "swap: the left app on the right" \
  test "$(key "$f" X-PlasmaFusion-PairRight)" = org.kde.dolphin.desktop
check "swap: the names follow" test "$(key "$f" Name)" = "Firefox · Dolphin"
check "swap: the split stays" test "$(key "$f" X-PlasmaFusion-PairShare)" = 0.3333
"$HELPER" open "$f"
call=$(last_call)
check "open by path: the dock's pairRequest, the apps and the split" \
  grep -q 'pairRequest", "[0-9]*:firefox.desktop:org.kde.dolphin.desktop:0.3333"' "$call"
check "open: the first screen's dock, else any" grep -q 'p.screen === 0' "$call"
"$HELPER" remove "$id"
check "remove: the entry is gone" test ! -e "$f"
check "remove: the other pairs stay" test "$(pairs)" = 2

# ---- 4. refused
refused() { ! "$HELPER" "$@" >/dev/null 2>&1; }
check "one app twice" refused save firefox.desktop firefox.desktop 0.5
check "no desktop file id" refused save firefox org.kde.dolphin.desktop 0.5
check "a path in an id" refused save ../x.desktop firefox.desktop 0.5
check "no split" refused save firefox.desktop org.kde.dolphin.desktop half
outside=$BASE/elsewhere/org.plasmafusion.pair-1.desktop
mkdir -p "${outside%/*}"
echo keep >"$outside"
"$HELPER" remove "$outside" >/dev/null 2>&1 || true
check "remove by a path elsewhere touches only the user's entries" test -f "$outside"
check "not a pair's id" refused remove org.kde.dolphin.desktop
check "swap of a pair that does not exist" refused swap org.plasmafusion.pair-0.desktop
check "an unknown command" refused list

echo "app pair helper: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
