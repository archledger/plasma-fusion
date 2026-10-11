#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of fusion-config.sh's search keys: which keys the launcher and KRunner get from the
# Windows-style set (apply_launcher_keys) and from an upgrade of a HOME an earlier release set up
# (apply_krunner_key_upgrade); and that the dock's Search button opens the launcher by default.
# The two functions and the shortcut helpers they call (shortcut_claim, shortcut_add,
# shortcut_remove) are taken out of fusion-config.sh as they are; kglobalaccel is a table in a file
# (shortcut_get, shortcut_set, key_holders over it) and plasmafusionrc is real (kreadconfig6,
# kwriteconfig6) in a throw-away XDG_CONFIG_HOME. Test tooling only, not installed; never touches
# the caller's configuration or shortcuts.
#
#   launcher-keys-unit.sh BASE
#
# BASE must be a scratch directory on disk (not /tmp); it is emptied first.
set -euo pipefail
BASE=${1:?scratch directory}
BASE=$(realpath -m -- "$BASE")
case $BASE in /tmp/* | /tmp) echo "use a directory on disk, not /tmp" >&2; exit 2 ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
TOOL=$HERE/../fusion-config.sh
rm -rf "${BASE:?}"
mkdir -p "$BASE"

# The functions, by name: a one-line "NAME() { ...; }", or from "NAME() {" to the first "}" at
# the start of a line.
extract() {
  local name
  for name in "$@"; do
    awk -v n="$name" '
      $0 ~ "^" n "\\(\\) \\{" { on = 1; print; if ($0 ~ /\}[[:space:]]*$/) exit; next }
      on { print } on && /^}/ { exit }' "$TOOL"
  done
}
LIB=$BASE/lib.sh
{
  grep -m1 '^UNSET=' "$TOOL"
  grep -m1 '^META=' "$TOOL"
  grep -m1 '^K_SPACE=' "$TOOL"
  grep -m1 '^LAUNCHER_ACTION=' "$TOOL"
  grep -m1 '^KRUNNER_KEY_VERSION=' "$TOOL" || echo 'KRUNNER_KEY_VERSION=missing'
  extract note read_key show set_key shortcut_add shortcut_remove shortcut_claim apply_launcher_keys \
    apply_krunner_key_upgrade
  cat <<'STUB'
# kglobalaccel as a table: "component<TAB>action<TAB>key key ..." per line in $KEYS.
shortcut_get() { awk -F'\t' -v c="$1" -v a="$2" '$1 == c && $2 == a { print $3 }' "$KEYS"; }
shortcut_set() {
  local comp=$1 action=$2
  shift 2
  awk -F'\t' -v c="$comp" -v a="$action" '!($1 == c && $2 == a)' "$KEYS" >"$KEYS.new"
  printf '%s\t%s\t%s\n' "$comp" "$action" "$*" >>"$KEYS.new"
  mv "$KEYS.new" "$KEYS"
}
key_holders() {
  awk -F'\t' -v k="$1" '{ n = split($3, ks, " "); for (i = 1; i <= n; i++) if (ks[i] == k) print $1 "\t" $2 }' "$KEYS"
}
STUB
} >"$LIB"
grep -q '^apply_launcher_keys() {' "$LIB" || { echo "FAIL: apply_launcher_keys was not found in fusion-config.sh"; exit 1; }

# Qt key codes: Meta+Space, Meta+S, Alt+Space, Alt+F2, Search, Meta+R.
MS=$((0x10000020)) MSS=$((0x10000053)) AS=$((0x08000020)) AF2=$((0x09000031)) SRCH=$((0x01000092)) MR=$((0x10000052))
LA="plasmashell	activate application launcher"
KR="org.kde.krunner.desktop	_launch"
KC="org.kde.krunner.desktop	RunClipboard"

PASS=0 FAIL=0
# CASE DESCRIPTION, FUNCTION, the table before (lines), marker before ("" none), the table wanted
# for the launcher and KRunner ("launcher keys|krunner keys"), marker wanted
run_case() {
  local desc=$1 fn=$2 before=$3 marker=$4 want=$5 want_marker=$6 home got
  home=$BASE/home-$((PASS + FAIL))
  mkdir -p "$home"
  printf '%b' "$before" >"$home/keys"
  [ -z "$marker" ] || printf '[Shortcuts]\nKRunnerKey=%s\n' "$marker" >"$home/plasmafusionrc"
  got=$(env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home" KEYS="$home/keys" bash -c '
    set -euo pipefail
    . "$1"
    DRY=0 CHANGES=0
    "$2" >/dev/null
    sorted() { tr " " "\n" | { grep . || true; } | sort -n | tr "\n" " " | sed "s/ $//"; }
    l=$(shortcut_get plasmashell "activate application launcher" | sorted)
    k=$(shortcut_get org.kde.krunner.desktop _launch | sorted)
    c=$(shortcut_get org.kde.krunner.desktop RunClipboard | sorted)
    m=$(kreadconfig6 --file plasmafusionrc --group Shortcuts --key KRunnerKey)
    echo "$l|$k|$c|$m"' _ "$LIB" "$fn" 2>&1) || got="(error: $got)"
  if [ "$got" = "$want|$want_marker" ]; then
    PASS=$((PASS + 1)); echo "PASS $desc"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $desc: got $got, want $want|$want_marker"
  fi
}
sorted() { tr " " "\n" | { grep . || true; } | sort -n | tr "\n" " " | sed "s/ $//"; }
keys() { echo "$*" | sorted; }

# A stock profile: KRunner has Alt+Space, Alt+F2 and Search, Shift+Alt+F2 runs the clipboard.
STOCK="$KR\t$AS $AF2 $SRCH\n$KC\t$((0x0B000031))\n"
run_case "Windows-style set: the search keys to the launcher, Alt+F2 stays with KRunner" apply_launcher_keys \
  "$STOCK" "" "$(keys $MS $MSS $AS $SRCH)|$AF2|" 1
run_case "Windows-style set: a key the user gave KRunner moves to the launcher, Alt+F2 does not" apply_launcher_keys \
  "$KR\t$MR\n" "" "$(keys $MS $MSS $AS $MR)|$AF2|" 1
run_case "Windows-style set again: Alt+F2 that an earlier release gave the launcher comes back to KRunner" \
  apply_launcher_keys "$LA\t$MS $MSS $AS $AF2 $SRCH\n$KR\t\n" 1 "$(keys $MS $MSS $AS $SRCH)|$AF2|" 1
# A HOME an earlier release set up: the launcher has all five keys, KRunner none.
OLD="$LA\t$MS $MSS $AS $AF2 $SRCH\n$KR\t\n$KC\t\n"
run_case "upgrade: Alt+F2 goes back to KRunner" apply_krunner_key_upgrade \
  "$OLD" "" "$(keys $MS $MSS $AS $SRCH)|$AF2|" 1
run_case "upgrade: a key the user gave KRunner since is kept, Alt+F2 stays with the launcher" apply_krunner_key_upgrade \
  "$LA\t$MS $MSS $AS $AF2 $SRCH\n$KR\t$MR\n" "" "$(keys $MS $MSS $AS $AF2 $SRCH)|$MR|" 1
run_case "upgrade: Alt+F2 the user gave away is not taken back" apply_krunner_key_upgrade \
  "$LA\t$MS $MSS $AS $SRCH\n$KR\t\n" "" "$(keys $MS $MSS $AS $SRCH)||" 1
run_case "upgrade once: Alt+F2 the user gave the launcher again after the upgrade stays there" apply_krunner_key_upgrade \
  "$OLD" 1 "$(keys $MS $MSS $AS $AF2 $SRCH)||" 1

# The dock's Search button agrees with the search keys: by default it opens the launcher too.
DOCK_XML=$HERE/../../../packages/plasmoids/org.plasmafusion.dock/contents/config/main.xml
search_default=$(python3 -c '
import sys, xml.etree.ElementTree as ET
ns = {"k": "http://www.kde.org/standards/kcfg/1.0"}
for e in ET.parse(sys.argv[1]).getroot().iter("{http://www.kde.org/standards/kcfg/1.0}entry"):
    if e.get("name") == "searchAction":
        print(e.find("k:default", ns).text)' "$DOCK_XML")
if [ "$search_default" = 1 ]; then
  PASS=$((PASS + 1)); echo "PASS the dock's Search button opens the launcher by default (searchAction 1)"
else
  FAIL=$((FAIL + 1)); echo "FAIL the dock's Search button default is searchAction $search_default, want 1 (the launcher)"
fi

echo "launcher-keys-unit: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
