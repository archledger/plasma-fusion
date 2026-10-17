#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of fusion-config.sh's command shortcuts (the Meta+N notification and Meta+V clipboard
# components, kglobalaccel desktop files that ask quick settings to open) and of Meta+Left/Right
# for the snap script's "Snap Left/Right" (snap sizes from the keyboard) against a fake
# kglobalaccel: the shortcut helpers, the components and the shell section's choice between the
# Windows-style set, --keep-shortcuts and a later run are taken out of fusion-config.sh as they
# are; `bus` and `bus_json` answer from a table of component, action, keys and whether a program
# is present (its key grabbed), made the way kglobalacceld 6.7 makes it: a component named *.desktop
# is read from its desktop file when the daemon first meets it in its session, which gives it a
# present _launch; an action registered under a name it does not know yet is added, not present, in
# place of one of the same name; an unregistered action goes, and a component left without actions
# is forgotten only at the daemon's next settings write-out (0.5 s later; the fake's "writeout"
# call); setShortcut with SetPresent makes an action present. Test tooling only, not installed; it
# talks to no bus.
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
  grep -m1 '^LAUNCHER_ACTION=' "$TOOL" || true
  grep -m1 '^K_LEFT=' "$TOOL" || true
  grep -m1 '^SNAP_CYCLE=' "$TOOL" || true
  grep -m1 '^SNAP_CYCLE_KEYS_VERSION=' "$TOOL" || true
  extract note keyname install_text shortcut_get shortcut_set shortcut_add shortcut_remove key_holders \
    shortcut_claim register_command_component command_key_present notify_desktop ensure_notify_shortcut clipboard_desktop \
    ensure_clipboard_shortcut read_key show set_key apply_clipboard_key_upgrade package_dir snap_script_reload \
    apply_snap_cycle_keys
} >"$LIB"
grep -q '^apply_snap_cycle_keys() {' "$LIB" || { echo "FAIL: apply_snap_cycle_keys was not found in fusion-config.sh"; exit 1; }
for f in ensure_notify_shortcut ensure_clipboard_shortcut; do
  grep -q "^$f() {" "$LIB" || { echo "FAIL: $f was not found in fusion-config.sh"; exit 1; }
done
STEP=$BASE/step.sh
shell_step >"$STEP"
grep -q 'ensure_clipboard_shortcut' "$STEP" || { echo "FAIL: the shell section does not set the clipboard key"; exit 1; }

# The fake kglobalaccel: $KGA holds "component<TAB>action<TAB>keys<TAB>present" lines (keys as Qt
# key codes, space-separated; present 1 when the key is grabbed and starts the action: a desktop
# file's _launch as read from the file, or an action given as present). $KGA.components lists the
# components the daemon knows (the case's rows at its start, then every one made, until a write-out
# finds it without actions).
FAKE=$BASE/fake.sh
cat >"$FAKE" <<'EOF'
kga() {
  python3 - "$KGA" "$@" <<'PY'
import json, os, sys
path, mode, args = sys.argv[1], sys.argv[2], sys.argv[3:]
rows = []
for line in open(path).read().splitlines():
    if line:
        comp, action, keys, present = (line.split("\t") + ["", ""])[:4]
        rows.append([comp, action, [int(k) for k in keys.split()], present == "1"])
known_path = path + ".components"
if os.path.exists(known_path):
    known = [c for c in open(known_path).read().splitlines() if c]
else:
    known = sorted(set(r[0] for r in rows))
call = args[args.index("org.kde.KGlobalAccel") + 1]
rest = args[args.index("org.kde.KGlobalAccel") + 2:]
def find(comp, action):
    for r in rows:
        if r[0] == comp and r[1] == action:
            return r
    return None
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
elif call == "setShortcut":
    # asaiu 4 COMPONENT ACTION NAME NAME N KEYS... FLAGS: NoAutoloading (4) sets the keys, SetPresent
    # (2) makes the action present (setShortcutKeys).
    comp, action, n = rest[2], rest[3], int(rest[6])
    keys = [int(k) for k in rest[7:7 + n]]
    flags = int(rest[7 + n])
    r = find(comp, action)
    if r is not None:
        if flags & 4:
            r[2] = keys
        if flags & 2:
            r[3] = True
    out = "ai %d" % (len(r[2]) if r is not None else 0)
elif call == "doRegister":
    comp, action = rest[2], rest[3]
    # kglobalacceld: findAction first; when the component is not known yet, getOrCreateComponent
    # reads a *.desktop component's file (its _launch, present), and fails without the file; then
    # addAction adds the named action anew, not present, in place of one of the same name.
    if find(comp, action) is None:
        made = comp in known
        if not made:
            if not comp.endswith(".desktop"):
                made = True
            elif os.path.isfile(os.path.join(os.environ["HOME"], ".local/share/kglobalaccel", comp)):
                rows.append([comp, "_launch", [], True])
                made = True
            if made:
                known.append(comp)
        if made:
            r = find(comp, action)
            if r is not None:
                rows.remove(r)
            rows.append([comp, action, [], False])
    out = ""
elif call == "writeout":
    # GlobalShortcutsRegistry::writeSettings: a component without actions is dropped.
    known = [c for c in known if any(r[0] == c for r in rows)]
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
with open(known_path, "w") as f:
    f.write("".join(c + "\n" for c in known))
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

# CASE NAME; then the run: "notify MODE", "ensure MODE" (Meta+V), "dry MODE", "step WINDOWS_SET
# SHORTCUTS" (the shell section), or "again-notify MODE" / "again-ensure MODE" (the step, then what
# fusion-restore.sh does to the component: its key back to none, _launch unregistered, the desktop
# file removed; then the step again at once, or with WROTE=1 after kglobalacceld's write-out); the
# table before as
# "component|action|keys|present" arguments. Leaves $H (the case's HOME).
run_case() {
  local name=$1 how=$2 arg1=$3 arg2=$4 row
  shift 4
  H=$BASE/$name
  mkdir -p "$H/backup"
  : >"$H/kga"
  : >"$H/backup/shortcuts"
  for row in "$@"; do printf '%s\n' "$row" | tr '|' '\t' >>"$H/kga"; done
  [ -z "${MARK:-}" ] || printf '[Shortcuts]\nClipboardKey=%s\n' "$MARK" >"$H/plasmafusionrc"
  [ -z "${SNAPMARK:-}" ] || printf '[Shortcuts]\nSnapCycleKeys=%s\n' "$SNAPMARK" >"$H/plasmafusionrc"
  # NO_RUNTIME=1: a session without XDG_RUNTIME_DIR.
  local runtime=(XDG_RUNTIME_DIR="$H/run")
  [ "${NO_RUNTIME:-0}" = 0 ] || runtime=()
  mkdir -p "$H/run"
  env -i PATH="$PATH" HOME="$H" XDG_CONFIG_HOME="$H" KGA="$H/kga" WROTE="${WROTE:-0}" "${runtime[@]}" bash -c '
    set -euo pipefail
    . "$1"; . "$2"
    DATA=$HOME/.local/share BACKUP=$HOME/backup CHANGES=0 DRY=0 INSTALL=
    case $3 in
      ensure) ensure_clipboard_shortcut "$4" ;;
      notify) ensure_notify_shortcut "$4" ;;
      again-notify | again-ensure)
        if [ "$3" = again-notify ]; then comp=$NOTIFY_COMPONENT step=ensure_notify_shortcut; else comp=$CLIPBOARD_COMPONENT step=ensure_clipboard_shortcut; fi
        "$step" "$4"
        bus call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel setForeignShortcut asai 4 "$comp" _launch "" "" 0 >/dev/null
        bus call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel unregister ss "$comp" _launch >/dev/null
        rm -f "$DATA/kglobalaccel/$comp"
        [ "$WROTE" != 1 ] || bus call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel writeout >/dev/null
        echo "== the step again"
        "$step" "$4" ;;
      dry) DRY=1; ensure_clipboard_shortcut "$4" ;;
      snapcycle)
        # The script registered its actions (KWin runs it).
        snap_cycle_actions_registered() { true; }
        apply_snap_cycle_keys "$4" ;;
      snapcycle-old)
        # An older snap script is running (an update in this session): loaded, without the new
        # actions (a KWin stand-in in front of the kglobalaccel one; its calls in
        # $HOME/kwin.calls). As in KWin 6.7.5 with Qt 6.11, a script started again from the path
        # KWin loaded it from at login is the older one (the QML engine keeps what it compiled by
        # its path); one loaded from another path that reaches the installed package is the new
        # one, with the actions.
        pkg=$DATA/kwin/scripts/plasmafusion-snap
        mkdir -p "$pkg/contents/ui"
        echo "{}" >"$pkg/metadata.json"
        echo "new" >"$pkg/contents/ui/main.qml"
        eval "fake_$(declare -f bus)"
        bus() {
          local a=("$@")
          [ "${a[0]}" = call ] && a=("${a[@]:1}")
          if [ "${a[0]}" = org.kde.KWin ]; then
            echo "${a[3]}" >>"$HOME/kwin.calls"
            case ${a[3]} in
              isScriptLoaded) if [ -f "$HOME/unloaded" ] && [ ! -f "$HOME/loaded" ]; then echo "b false"; else echo "b true"; fi ;;
              unloadScript) : >"$HOME/unloaded"; echo "b true" ;;
              loadDeclarativeScript)
                printf "%s\n" "${a[5]}" >"$HOME/loaded"
                echo "i 3" ;;
              start)
                if [ -f "$HOME/loaded" ] && [ "$(sed -n 1p "$HOME/loaded")" != "$pkg/contents/ui/main.qml" ] &&
                  [ "$(cat "$(sed -n 1p "$HOME/loaded")" 2>/dev/null)" = new ]; then
                  : >"$HOME/started"
                fi ;;
            esac
            return 0
          fi
          fake_bus "$@"
        }
        snap_cycle_actions_registered() { [ -f "$HOME/started" ]; }
        apply_snap_cycle_keys "$4" ;;
      step | step-notify)
        has_name() { true; }
        ensure_widget_shortcut() { :; }
        # step-notify runs the Meta+N step as well; step leaves it out.
        [ "$3" = step-notify ] || ensure_notify_shortcut() { :; }
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
# fusion-restore.sh, then the setup again within kglobalacceld's 0.5 s write-out: it still knows
# the component, without its _launch, so registering it gave no _launch and the key was set on
# nothing although the step said "none -> Meta+N"; it worked only after the next login.
run_case notify-again again-notify claim "" "kwin|Walk Through Windows|"
expect_keys "the setup right after a restore's unregister (within the write-out) gives Meta+N to the notification list" "$NOTIFY" _launch "$META_N"
expect_launches "  and Meta+N starts the command at once (no login needed)" "$NOTIFY"
run_case notify-again-free again-notify free ""
expect_keys "the same with a later run's free Meta+N" "$NOTIFY" _launch "$META_N"
expect_launches "  starting the command at once" "$NOTIFY"
# After the write-out the component is made from its file again (the key worked before as well).
WROTE=1 run_case notify-again-later again-notify claim "" "kwin|Walk Through Windows|"
expect_keys "the setup again after kglobalacceld's write-out gives Meta+N" "$NOTIFY" _launch "$META_N"
expect_launches "  and Meta+N starts the command at once" "$NOTIFY"
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

# The same for Meta+V: Klipper got it back, the setup right after takes it again.
run_case claim-again again-ensure claim "" "$KLIPPER"
expect_keys "the setup right after a restore's unregister gives Meta+V to the clipboard sheet" "$COMP" _launch "$META_V"
expect_launches "  and Meta+V opens the sheet at once" "$COMP"
# Without a key (Klipper keeps Meta+V), the component's _launch is there and present, so a key given
# to it later in System Settings works at once.
run_case free-again again-ensure free "" "$KLIPPER"
expect_keys "a later run right after a restore leaves Meta+V to Klipper's pop-up" plasmashell show-on-mouse-pos "$META_V"
expect_launches "  and the component is there for a key from System Settings" "$COMP"

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

# An upgrade from 0.4 (the Windows-style set ran then: Meta+N is the notification list's and Meta+S
# the launcher's): Meta+V moves to the sheet once; the mark keeps a later run from taking it again.
META_S=$((0x10000000 + 0x53))
LAUNCHER="plasmashell|activate application launcher|$META_S"
run_case step-upgrade step 0 auto "$KLIPPER" "$NOTIFY|_launch|$META_N|1" "$LAUNCHER"
expect_keys "an upgraded Windows-style setup gives Meta+V to the clipboard sheet" "$COMP" _launch "$META_V"
expect_keys "  and Klipper's pop-up loses it" plasmashell show-on-mouse-pos ""
if grep -qx 'ClipboardKey=1' "$H/plasmafusionrc" 2>/dev/null; then pass "  once: the run is marked"; else fail "  the run is not marked"; fi
MARK=1 run_case step-upgrade-done step 0 auto "$KLIPPER" "$NOTIFY|_launch|$META_N|1" "$LAUNCHER"
expect_keys "after the mark Meta+V stays where the user put it" plasmashell show-on-mouse-pos "$META_V"
# --keep-shortcuts before (Meta+N is quick settings', the notification component has no key):
# Klipper keeps Meta+V.
run_case step-upgrade-kept step 0 auto "$KLIPPER" "$NOTIFY|_launch||1"
expect_keys "a setup made with --keep-shortcuts leaves Meta+V to Klipper's pop-up" plasmashell show-on-mouse-pos "$META_V"
# A key the user gave the sheet stays.
run_case step-upgrade-user step 0 auto "$KLIPPER" "$NOTIFY|_launch|$META_N|1" "$LAUNCHER" "$COMP|_launch|$META_SHIFT_V|1"
expect_keys "the sheet's own key from the user stays" "$COMP" _launch "$META_SHIFT_V"
expect_keys "  and Klipper keeps Meta+V" plasmashell show-on-mouse-pos "$META_V"

# A former --keep-shortcuts setup whose quick settings lost Meta+N: this run's Meta+N step gives
# the notification list the free key, which must not count as the Windows-style set's mark.
run_case step-keep-freed step-notify 0 auto "$KLIPPER"
expect_keys "a --keep-shortcuts setup with Meta+N freed: the notification list takes Meta+N" "$NOTIFY" _launch "$META_N"
expect_keys "  but Klipper's pop-up keeps Meta+V" plasmashell show-on-mouse-pos "$META_V"
# ... and one where an earlier run did that already: Meta+N alone is not the mark.
run_case step-keep-earlier step 0 auto "$KLIPPER" "$NOTIFY|_launch|$META_N|1"
expect_keys "a --keep-shortcuts setup whose Meta+N went to the notification list earlier keeps Klipper's Meta+V" \
  plasmashell show-on-mouse-pos "$META_V"

# ---- Meta+Left/Right: snap sizes from the keyboard (the snap script's Snap Left/Right)
META_LEFT=$((0x10000000 + 0x01000012)) META_RIGHT=$((0x10000000 + 0x01000014)) META_SHIFT_LEFT=$((0x10000000 + 0x02000000 + 0x01000012))
TILE_L="kwin|Window Quick Tile Left|$META_LEFT|1" TILE_R="kwin|Window Quick Tile Right|$META_RIGHT|1"
SNAP_L="kwin|Plasma Fusion: Snap Left||1" SNAP_R="kwin|Plasma Fusion: Snap Right||1"
run_case snap-claim snapcycle claim "" "$TILE_L" "$TILE_R" "$SNAP_L" "$SNAP_R"
expect_keys "the Windows-style set gives Meta+Left to Snap Left" kwin "Plasma Fusion: Snap Left" "$META_LEFT"
expect_keys "  and Meta+Right to Snap Right" kwin "Plasma Fusion: Snap Right" "$META_RIGHT"
expect_keys "  KWin's quick tile left loses it" kwin "Window Quick Tile Left" ""
expect_keys "  and quick tile right" kwin "Window Quick Tile Right" ""
if grep -q "Window Quick Tile Left" "$H/backup/shortcuts"; then pass "  the backup records KWin's key (fusion-restore.sh gives it back)"
else fail "  the backup does not record KWin's key"; fi
if grep -qx 'SnapCycleKeys=1' "$H/plasmafusionrc" 2>/dev/null; then pass "  the run is marked"; else fail "  the run is not marked"; fi
run_case snap-migrate snapcycle migrate "" "$TILE_L" "$TILE_R" "$SNAP_L" "$SNAP_R"
expect_keys "an update (no Windows-style set) moves Meta+Left from KWin's default too, once" kwin "Plasma Fusion: Snap Left" "$META_LEFT"
expect_keys "  and Meta+Right" kwin "Plasma Fusion: Snap Right" "$META_RIGHT"
run_case snap-migrate-old snapcycle-old migrate "" "$TILE_L" "$TILE_R" "$SNAP_L" "$SNAP_R"
expect_keys "an update while an older snap script runs: the new one is loaded and Meta+Left moves" kwin "Plasma Fusion: Snap Left" "$META_LEFT"
if [ "$(tr '\n' ' ' <"$H/kwin.calls" 2>/dev/null)" = "isScriptLoaded unloadScript isScriptLoaded loadDeclarativeScript start " ]; then
  pass "  unloaded, then loaded and started once it was gone"
else
  fail "  KWin calls: $(tr '\n' ' ' <"$H/kwin.calls" 2>/dev/null)"
fi
loaded=$(sed -n 1p "$H/loaded" 2>/dev/null)
if [[ $loaded == "$H/run/plasma-fusion/kwin-scripts/plasmafusion-snap-"*/contents/ui/main.qml ]] &&
  [ "$(readlink "${loaded%/contents/ui/main.qml}")" = "$H/.local/share/kwin/scripts/plasmafusion-snap" ]; then
  pass "  from a link in the runtime directory to the installed package (a path KWin has not compiled)"
else
  fail "  loaded from '$loaded'"
fi
if grep -qx 'SnapCycleKeys=1' "$H/plasmafusionrc" 2>/dev/null; then pass "  and the run is marked"; else fail "  the run is not marked"; fi
if grep -q "loaded again from the installed files" "$H/log"; then pass "  and says so"; else fail "  the log: $(grep 'snap sizes' "$H/log")"; fi
NO_RUNTIME=1 run_case snap-migrate-old-noruntime snapcycle-old migrate "" "$TILE_L" "$TILE_R" "$SNAP_L" "$SNAP_R"
expect_keys "without a runtime directory the older script stays: Meta+Left stays KWin's" kwin "Window Quick Tile Left" "$META_LEFT"
if [ "$(tr '\n' ' ' <"$H/kwin.calls" 2>/dev/null)" = "isScriptLoaded " ] && ! grep -q SnapCycleKeys "$H/plasmafusionrc" 2>/dev/null &&
  grep -q "the new one comes with the next login" "$H/log"; then
  pass "  not unloaded, the run not marked (the next update moves the keys), and the log says when"
else
  fail "  KWin calls: $(tr '\n' ' ' <"$H/kwin.calls" 2>/dev/null), log: $(grep 'snap sizes' "$H/log")"
fi
SNAPMARK=1 run_case snap-migrate-done snapcycle migrate "" "$TILE_L" "$TILE_R" "$SNAP_L" "$SNAP_R"
expect_keys "after the mark, Meta+Left the user gave back to KWin's quick tile stays there" kwin "Window Quick Tile Left" "$META_LEFT"
expect_keys "  and Snap Left gets nothing" kwin "Plasma Fusion: Snap Left" ""
run_case snap-migrate-user snapcycle migrate "" "kwin|Window Quick Tile Left||1" "kwin|Switch Window Left|$META_LEFT|1" "$TILE_R" "$SNAP_L" "$SNAP_R"
expect_keys "an update leaves Meta+Left where the user put it (another action)" kwin "Switch Window Left" "$META_LEFT"
expect_keys "  Snap Left gets nothing" kwin "Plasma Fusion: Snap Left" ""
expect_keys "  while Meta+Right, still KWin's, moves" kwin "Plasma Fusion: Snap Right" "$META_RIGHT"
run_case snap-claim-own snapcycle claim "" "$TILE_L" "$TILE_R" "kwin|Plasma Fusion: Snap Left|$META_SHIFT_LEFT|1" "$SNAP_R"
expect_keys "the Windows-style set adds Meta+Left to a Snap Left key the user gave (both kept)" kwin "Plasma Fusion: Snap Left" "$META_LEFT $META_SHIFT_LEFT"

echo "shortcut-keys-unit: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
