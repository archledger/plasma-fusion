#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of fusion-config.sh's command shortcuts (the Meta+N notification and Meta+V clipboard
# components, kglobalaccel desktop files that ask quick settings to open) against a fake
# kglobalaccel: the shortcut helpers, the components and the shell section's choice between the
# Windows-style set, --keep-shortcuts and a later run are taken out of fusion-config.sh as they
# are; `bus` and `bus_json` answer from a table of component, action, keys and whether a program
# owns the action, made the way kglobalacceld 6.7 makes it (a component named *.desktop is read
# from its desktop file when it is first named, and an action registered under a name it does not
# know yet replaces the file's own). Test tooling only, not installed; it talks to no bus.
#
#   shortcut-keys-unit.sh BASE
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

# The functions, by name: from "NAME() {" to the first "}" at the start of a line.
extract() {
  local name
  for name in "$@"; do
    awk -v n="$name" '
      $0 ~ "^" n "\\(\\) \\{" { on = 1; print; if ($0 ~ /\}[[:space:]]*$/) exit; next }
      on { print } on && /^}/ { exit }' "$TOOL"
  done
}
# The shell section's shortcut choice: from its comment to the end of its if.
shell_step() {
  awk '/^# Quick settings: Meta\+A / { on = 1 } on { print } on && /^fi$/ { exit }' "$TOOL"
}
LIB=$BASE/lib.sh
{
  grep -m1 '^META=' "$TOOL" || true
  grep -m1 '^NOTIFY_COMPONENT=' "$TOOL" || true
  grep -m1 '^NOTIFY_SHORTCUT=' "$TOOL" || true
  grep -m1 '^NOTIFY_JS=' "$TOOL" || true
  grep -m1 '^CLIPBOARD_COMPONENT=' "$TOOL" || true
  grep -m1 '^CLIPBOARD_SHORTCUT=' "$TOOL" || true
  grep -m1 '^CLIPBOARD_JS=' "$TOOL" || true
  grep -m1 '^CLIPBOARD_KEY_VERSION=' "$TOOL" || true
  grep -m1 '^UNSET=' "$TOOL" || true
  extract note keyname install_text shortcut_get shortcut_set shortcut_add shortcut_remove key_holders \
    shortcut_claim register_command_component notify_desktop ensure_notify_shortcut clipboard_desktop \
    ensure_clipboard_shortcut read_key show set_key apply_clipboard_key_upgrade
} >"$LIB"
for f in ensure_notify_shortcut ensure_clipboard_shortcut; do
  grep -q "^$f() {" "$LIB" || { echo "FAIL: $f was not found in fusion-config.sh"; exit 1; }
done
STEP=$BASE/step.sh
shell_step >"$STEP"
grep -q 'ensure_clipboard_shortcut' "$STEP" || { echo "FAIL: the shell section does not set the clipboard key"; exit 1; }

# The fake kglobalaccel: $KGA holds "component<TAB>action<TAB>keys<TAB>owned" lines (keys as Qt key
# codes, space-separated; owned 1 when the action starts something: a desktop file's _launch).
FAKE=$BASE/fake.sh
cat >"$FAKE" <<'EOF'
kga() {
  python3 - "$KGA" "$@" <<'PY'
import json, os, sys
path, mode, args = sys.argv[1], sys.argv[2], sys.argv[3:]
rows = []
for line in open(path).read().splitlines():
    if line:
        comp, action, keys, owned = (line.split("\t") + ["", ""])[:4]
        rows.append([comp, action, [int(k) for k in keys.split()], owned == "1"])
call = args[args.index("org.kde.KGlobalAccel") + 1]
rest = args[args.index("org.kde.KGlobalAccel") + 2:]
def find(comp, action):
    for r in rows:
        if r[0] == comp and r[1] == action:
            return r
    return None
def component_exists(comp):
    return any(r[0] == comp for r in rows)
out = None
if call == "shortcut":
    r = find(rest[2], rest[3])
    # A desktop file's action without a key reads as the key 0 (kglobalacceld 6.7).
    out = {"type": "ai", "data": [(r[2] or ([0] if r[3] else [])) if r else []]}
elif call == "globalShortcutsByKey":
    key = int(rest[2])
    out = {"type": "a(ssssssaiai)", "data": [[[r[1], r[1], r[0], r[0], "", "", r[2], r[2]] for r in rows if key in r[2]]]}
elif call == "setForeignShortcut":
    comp, action, n = rest[2], rest[3], int(rest[6])
    keys = [int(k) for k in rest[7:7 + n]]
    r = find(comp, action)
    if r is not None:
        r[2] = keys
    out = "ai %d" % (len(keys) if r is not None else 0)
elif call == "doRegister":
    comp, action = rest[2], rest[3]
    # kglobalacceld: findAction first; when the component does not exist yet, getOrCreateComponent
    # reads a *.desktop component's file (its _launch, owned), then addAction adds the named action
    # as a new one, unowned, in place of one of the same name.
    if find(comp, action) is None:
        if not component_exists(comp) and comp.endswith(".desktop") and \
                os.path.isfile(os.path.join(os.environ["HOME"], ".local/share/kglobalaccel", comp)):
            rows.append([comp, "_launch", [], True])
        r = find(comp, action)
        if r is not None:
            rows.remove(r)
        rows.append([comp, action, [], False])
    out = ""
elif call == "unregister":
    r = find(rest[1], rest[2])
    if r is not None:
        rows.remove(r)
    out = "b %s" % ("true" if r is not None else "false")
else:
    sys.exit("fake kglobalaccel: no answer for " + call)
with open(path, "w") as f:
    for r in rows:
        f.write("%s\t%s\t%s\t%d\n" % (r[0], r[1], " ".join(str(k) for k in r[2]), r[3]))
with open(path + ".calls", "a") as f:
    f.write(call + " " + " ".join(rest) + "\n")
print(json.dumps(out) if mode == "json" else out)
PY
}
bus() { [ "${1:-}" = call ] && shift; kga text "$@"; }
bus_json() { [ "${1:-}" = call ] && shift; kga json "$@"; }
EOF

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); echo "PASS $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
# Qt key codes.
META_V=$((0x10000000 + 0x56)) META_SHIFT_V=$((0x10000000 + 0x02000000 + 0x56)) CTRL_ALT_V=$((0x04000000 + 0x08000000 + 0x56))
COMP=org.plasmafusion.clipboard.desktop

# CASE NAME; then the run: "notify MODE", "ensure MODE" (Meta+V), "dry MODE" or "step WINDOWS_SET
# SHORTCUTS" (the shell section); the table before as "component|action|keys|owned" arguments.
# Leaves $H (the case's HOME).
run_case() {
  local name=$1 how=$2 arg1=$3 arg2=$4 row
  shift 4
  H=$BASE/$name
  mkdir -p "$H/backup"
  : >"$H/kga"
  : >"$H/backup/shortcuts"
  for row in "$@"; do printf '%s\n' "$row" | tr '|' '\t' >>"$H/kga"; done
  [ -z "${MARK:-}" ] || printf '[Shortcuts]\nClipboardKey=%s\n' "$MARK" >"$H/plasmafusionrc"
  env -i PATH="$PATH" HOME="$H" XDG_CONFIG_HOME="$H" KGA="$H/kga" bash -c '
    set -euo pipefail
    . "$1"; . "$2"
    DATA=$HOME/.local/share BACKUP=$HOME/backup CHANGES=0 DRY=0
    case $3 in
      ensure) ensure_clipboard_shortcut "$4" ;;
      notify) ensure_notify_shortcut "$4" ;;
      dry) DRY=1; ensure_clipboard_shortcut "$4" ;;
      step)
        has_name() { true; }
        ensure_widget_shortcut() { :; }
        ensure_notify_shortcut() { :; }
        WINDOWS_SET=$4 SHORTCUTS=$5 QS_SHORTCUT=0 QS_SHORTCUT_TEXT= QS_OLD_SHORTCUT=0 QS_OLD_SHORTCUT_TEXT=
        . "$6" ;;
    esac' _ "$LIB" "$FAKE" "$how" "$arg1" "$arg2" "$STEP" >"$H/log" 2>&1 || { fail "$name: the step failed: $(tail -3 "$H/log")"; return 0; }
}
keys_of() { awk -F'\t' -v c="$1" -v a="$2" '$1 == c && $2 == a { print $3 }' "$H/kga"; }
# The key starts the component's command: its _launch is the desktop file's own, and no other
# (empty) action is left behind.
expect_launches() { # DESCRIPTION COMPONENT
  local rows
  rows=$(awk -F'\t' -v c="$2" '$1 == c { print $2 "=" $4 }' "$H/kga" | tr '\n' ' ')
  if [ "$rows" = "_launch=1 " ]; then pass "$1"; else fail "$1: $2 has '$rows', want '_launch=1 '"; fi
}
expect_keys() { # DESCRIPTION COMPONENT ACTION WANTED
  local got
  got=$(keys_of "$2" "$3")
  if [ "$got" = "$4" ]; then pass "$1"; else fail "$1: $2 / $3 = '$got', want '$4'"; fi
}

# Meta+N, the notification list's component: its key starts the command at once (before, it took
# the next login, as kglobalaccel read the desktop file again only then).
NOTIFY=org.plasmafusion.notifications.desktop META_N=$((0x10000000 + 0x4e))
run_case notify notify claim "" "kwin|Walk Through Windows|"
expect_keys "the Windows-style set gives Meta+N (and nothing else) to the notification list" "$NOTIFY" _launch "$META_N"
expect_launches "Meta+N starts the component's command at once (no login needed)" "$NOTIFY"
# A component kglobalaccel already read at login (its desktop file there before) keeps working.
run_case notify-known notify claim "" "$NOTIFY|_launch||1"
expect_launches "an already loaded component keeps its own _launch" "$NOTIFY"

# ---- Meta+V, the clipboard sheet's component
KLIPPER="plasmashell|show-on-mouse-pos|$META_V"

# The Windows-style set: Meta+V moves from Klipper's pop-up to the sheet, and the backup records
# Klipper's key so that fusion-restore.sh gives it back.
run_case claim ensure claim "" "$KLIPPER"
expect_keys "the Windows-style set gives Meta+V (and nothing else) to the clipboard sheet" "$COMP" _launch "$META_V"
expect_keys "Klipper's pop-up loses Meta+V" plasmashell show-on-mouse-pos ""
if grep -qxF "plasmashell"$'\t'"show-on-mouse-pos"$'\t'"$META_V" "$H/backup/shortcuts"; then
  pass "Klipper's old key is in the backup for fusion-restore.sh"
else
  fail "Klipper's old key is not in the backup: $(cat "$H/backup/shortcuts")"
fi
f=$H/.local/share/kglobalaccel/$COMP
if [ -f "$f" ] && [ "$(stat -c %a "$f")" = 755 ] && grep -q "openRequest','clipboard:'" "$f" && grep -q '^Name=Plasma Fusion: Clipboard$' "$f"; then
  pass "the component's desktop file is executable and asks for the clipboard sheet"
else
  fail "the component's desktop file: $(ls -l "$f" 2>&1)"
fi
expect_launches "Meta+V starts the component's command at once (no login needed)" "$COMP"

# Klipper's other keys stay.
run_case claim-other ensure claim "" "plasmashell|show-on-mouse-pos|$META_V $CTRL_ALT_V"
expect_keys "Klipper's pop-up keeps its other keys" plasmashell show-on-mouse-pos "$CTRL_ALT_V"

# A later run without the set: Klipper keeps Meta+V; the component is there without a key.
run_case free-stock ensure free "" "$KLIPPER"
expect_keys "a later run leaves Meta+V to Klipper's pop-up" plasmashell show-on-mouse-pos "$META_V"
expect_keys "a later run gives the sheet no key while Klipper has it" "$COMP" _launch ""
# ... but takes a free Meta+V.
run_case free-unused ensure free "" "plasmashell|show-on-mouse-pos|"
expect_keys "a later run gives a free Meta+V to the sheet" "$COMP" _launch "$META_V"
# A key the user gave the sheet is kept.
run_case free-user ensure free "" "$KLIPPER" "$COMP|_launch|$META_SHIFT_V|1"
expect_keys "a later run keeps the user's key for the sheet" "$COMP" _launch "$META_SHIFT_V"
expect_keys "... and Klipper's" plasmashell show-on-mouse-pos "$META_V"

# A dry run changes nothing.
run_case dry dry claim "" "$KLIPPER"
expect_keys "a dry run leaves Klipper's key" plasmashell show-on-mouse-pos "$META_V"
if [ ! -e "$H/.local/share/kglobalaccel/$COMP" ] && [ ! -s "$H/backup/shortcuts" ]; then pass "a dry run writes nothing"; else fail "a dry run wrote files"; fi

# The shell section: which mode each kind of run uses.
run_case step-set step 1 auto "$KLIPPER"
expect_keys "the shell section with the Windows-style set claims Meta+V" "$COMP" _launch "$META_V"
run_case step-keep step 0 keep "$KLIPPER"
expect_keys "--keep-shortcuts leaves Meta+V to Klipper's pop-up" plasmashell show-on-mouse-pos "$META_V"
if [ ! -e "$H/.local/share/kglobalaccel/$COMP" ] && [ -z "$(keys_of "$COMP" _launch)" ] && ! grep -q "$COMP" "$H/kga"; then
  pass "--keep-shortcuts adds no clipboard component"
else
  fail "--keep-shortcuts added the clipboard component"
fi
run_case step-later step 0 auto "$KLIPPER"
expect_keys "a later run (set applied before) leaves Klipper's Meta+V" plasmashell show-on-mouse-pos "$META_V"
expect_launches "a later run registers the component (for System Settings)" "$COMP"

# An upgrade from 0.4 (the Windows-style set ran then: Meta+N is the notification list's): Meta+V
# moves to the sheet once; the mark keeps a later run from taking it again.
run_case step-upgrade step 0 auto "$KLIPPER" "$NOTIFY|_launch|$META_N|1"
expect_keys "an upgraded Windows-style setup gives Meta+V to the clipboard sheet" "$COMP" _launch "$META_V"
expect_keys "  and Klipper's pop-up loses it" plasmashell show-on-mouse-pos ""
if grep -qx 'ClipboardKey=1' "$H/plasmafusionrc" 2>/dev/null; then pass "  once: the run is marked"; else fail "  the run is not marked"; fi
MARK=1 run_case step-upgrade-done step 0 auto "$KLIPPER" "$NOTIFY|_launch|$META_N|1"
expect_keys "after the mark Meta+V stays where the user put it" plasmashell show-on-mouse-pos "$META_V"
# --keep-shortcuts before (Meta+N is quick settings', the notification component has no key):
# Klipper keeps Meta+V.
run_case step-upgrade-kept step 0 auto "$KLIPPER" "$NOTIFY|_launch||1"
expect_keys "a setup made with --keep-shortcuts leaves Meta+V to Klipper's pop-up" plasmashell show-on-mouse-pos "$META_V"
# A key the user gave the sheet stays.
run_case step-upgrade-user step 0 auto "$KLIPPER" "$NOTIFY|_launch|$META_N|1" "$COMP|_launch|$META_SHIFT_V|1"
expect_keys "the sheet's own key from the user stays" "$COMP" _launch "$META_SHIFT_V"
expect_keys "  and Klipper keeps Meta+V" plasmashell show-on-mouse-pos "$META_V"

echo "shortcut-keys-unit: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
