#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Copy text from the screen in one step (plasma-fusion-copytext) in a private session: the real
# Spectacle, Tesseract, Klipper and notification server, keys and a pointer drag through KWin. First
# the session holds 0.5.0's Meta+Shift+T component (spectacle --region), as after an update in a
# running session: its key starts Spectacle's region capture. The Fusion setup then makes the
# component again with the helper (kglobalaccel keeps a loaded component's command otherwise),
# keeping the key. A maximized window shows two known lines (where KWin placed its content: the
# drags follow); then:
#   1. Meta+Shift+T, an area dragged around the first line, released (no Return: the area is
#      taken as the drag ends): Klipper's clipboard holds the line, "Text copied" is notified, no
#      image is left (runtime directory, Pictures), no Spectacle keeps running;
#   2. Meta+Shift+T, Esc: nothing is copied or notified, the helper ends;
#   3. with Spectacle's window open: Meta+Shift+T, the area, Return: the helper leaves the capture to
#      that Spectacle (spectacle --region), which shows it in its window (Extract Text there) and
#      keeps running; the helper copies nothing;
#   4. the second line the same way, after Spectacle was closed: the clipboard follows;
#   5. quick settings' header button (Meta+A, the button left of System Settings): the first line
#      again, the clipboard follows;
#   6. the clipboard sheet's copy-text button (Meta+V, the button before Emoji, where quick
#      settings' dump puts it): the second line again, the clipboard follows, the sheet is closed;
#   7. the top bar's copy-text button (before the clipboard button, where the dump puts it): the
#      first line again, the clipboard follows.
# Screenshots are taken only while no Spectacle runs: the session's shot is a Spectacle request too,
# and Spectacle takes it over (an area being chosen, an open window).
# Run: tools/vsession/vsession.sh ct-1 packages/copytext/tests/vsession/scenario-copytext.sh 1440x900 300
# (HOME seeded with the stage in ~/pf-stage and tools/ in ~/pf-tools; on a host with the
# plasma-fusion-copytext package, PLASMA_FUSION_COPYTEXT_NO_OVERLAY=1 in ~/.config/pfv-env, else the
# session bus starts that package's overlay in place of Spectacle's selection).
exec 2>&1
export OUT
set -euo pipefail
set -x
CHK=$OUT/checks.txt
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
trap 'fail "the scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }

LINE1="Plasma Fusion copies 4812 words"
LINE2="Second line from the screen 2026"
clip() { qdbus org.kde.klipper /klipper org.kde.klipper.klipper.getClipboardContents 2>/dev/null || true; }
# Processes of this session whose command line holds PATTERN.
procs() {
  local p
  for p in /proc/[0-9]*; do
    tr '\0' ' ' <"$p/cmdline" 2>/dev/null | grep -q -- "$1" || continue
    grep -qz "^XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR\$" "$p/environ" 2>/dev/null && echo "${p#/proc/}"
  done
  return 0
}
# Wait until no helper runs (max $1 s of the clock: a round scans every process, which takes a while
# under set -x, so counting rounds made a helper that stays a wait longer than the session).
helper_done() {
  local end=$((SECONDS + $1))
  while [ "$SECONDS" -lt "$end" ]; do
    [ -n "$(procs plasma-fusion-copytext)" ] || return 0
    sleep 0.2
  done
  return 1
}
notified() { grep -c "string \"$1\"" "$OUT/notify-monitor.log" || true; }
images() { { find "$HOME/Pictures" "$XDG_RUNTIME_DIR" -name '*.png' 2>/dev/null || true; } | wc -l; }
leftover() { find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'plasma-fusion-copytext.*' ! -name plasma-fusion-copytext.lock; }
# The target's content origin on the screen: "X Y".
origin() {
  K run "var l = workspace.windowList(), r = ''; for (var i = 0; i < l.length; ++i) {
    if (String(l[i].caption) === 'copytext-target') { var g = l[i].clientGeometry; r = Math.round(g.x) + ' ' + Math.round(g.y); } }
    report(r);" | python3 -c 'import json, sys; print(json.load(sys.stdin))'
}
# Normal windows of Spectacle.
spectacle_windows() {
  K run "var l = workspace.windowList(), n = 0; for (var i = 0; i < l.length; ++i) {
    if (l[i].normalWindow && String(l[i].resourceClass).indexOf('spectacle') >= 0) { n++; } } report(n);"
}
# 1|2 [return]: Meta+Shift+T, a drag around the line (the content's 160,200 or 160,440, 32 px); the
# helper's capture takes the area as the drag ends (-k), an open Spectacle's own on Return.
select_line() {
  local y=$((OY + ($1 == 1 ? 200 : 440)))
  pfinput 'key meta+shift+t'
  sleep 5
  if [ "${2:-}" = return ]; then
    pfinput "drag $((OX + 130)) $((y - 30)) $((OX + 820)) $((y + 70)) 20" 'sleep 0.6' 'key return'
  else
    pfinput "drag $((OX + 130)) $((y - 30)) $((OX + 820)) $((y + 70)) 20"
  fi
}

# ---- 0.5.0's component, loaded and given Meta+Shift+T as 0.5.0's setup did
COMP=$HOME/.local/share/kglobalaccel/org.plasmafusion.copytext.desktop
mkdir -p "$(dirname "$COMP")"
cat >"$COMP" <<'EOF'
[Desktop Entry]
Type=Application
Name=Plasma Fusion: Copy Text from Screen
Comment=Select an area with Spectacle and choose Extract Text to copy its text (installed by Plasma Fusion's fusion-config.sh, removed by fusion-restore.sh)
Icon=document-scan
Exec=spectacle --region
StartupNotify=false
EOF
chmod 0755 "$COMP"
KEY=$((0x10000000 + 0x02000000 + 0x54))
NAME="Plasma Fusion: Copy Text from Screen"
busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel doRegister as 4 org.plasmafusion.copytext.desktop _launch "$NAME" "$NAME"
busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel setForeignShortcut asai 4 org.plasmafusion.copytext.desktop _launch "" "" 1 "$KEY"
busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel setShortcut asaiu 4 org.plasmafusion.copytext.desktop _launch "$NAME" "$NAME" 1 "$KEY" 6 >/dev/null
sleep 1
pfinput 'key meta+shift+t'
sleep 5
[ -n "$(procs 'spectacle --region')" ] && pass "0: before the setup, 0.5.0's Meta+Shift+T starts spectacle --region" ||
  fail "0: 0.5.0's key did not start spectacle --region ($(procs spectacle | tr '\n' ' '))"
pfinput 'key escape'
sleep 2
for p in $(procs spectacle); do kill "$p" 2>/dev/null || true; done
sleep 1

# ---- the Fusion setup
fc_rc=0
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || fc_rc=$?
info "fusion-config rc=$fc_rc"
grep -a 'copy text\|copytext' "$OUT/fc.log" >>"$CHK" || true
HELPER=$HOME/.local/libexec/plasma-fusion/plasma-fusion-copytext
grep -qx "Exec=$HELPER" "$COMP" && pass "Meta+Shift+T's component runs the helper ($HELPER)" ||
  fail "the component's command: $(grep '^Exec=' "$COMP" 2>&1)"
grep -qa 'reload org.plasmafusion.copytext.desktop' "$OUT/fc.log" && pass "the setup made the loaded 0.5.0 component again" ||
  fail "the setup did not reload the component"
keys=$(busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel shortcut as 4 org.plasmafusion.copytext.desktop _launch "" "")
[ "$keys" = "ai 1 $KEY" ] && pass "Meta+Shift+T is kept through the reload" || fail "the key after the setup: $keys"
sleep 3
qdbus | grep -qx ' *org.kde.klipper' && pass "Klipper is on the session bus" || fail "no Klipper on the session bus"
info "tesseract: $(tesseract --version 2>&1 | head -1); languages: $(tesseract --list-langs 2>/dev/null | tail -n +2 | tr '\n' ' ')"
info "spectacle: $(spectacle --version 2>&1 | head -1)"

dbus-monitor --session "type='method_call',interface='org.freedesktop.Notifications',member='Notify'" \
  >"$OUT/notify-monitor.log" 2>&1 &
MON=$!
cat >"$OUT/target.qml" <<EOF
import QtQuick
import QtQuick.Window
Window {
    visible: true
    visibility: Window.Maximized
    color: "#f4f5f7"
    title: "copytext-target"
    Text { x: 160; y: 200; text: "$LINE1"; font.pixelSize: 32; color: "#17181c" }
    Text { x: 160; y: 440; text: "$LINE2"; font.pixelSize: 32; color: "#17181c" }
}
EOF
# Qt's qml tool: qml6 on Arch, qml-qt6 on Fedora (qt6-qtdeclarative-devel, which the build and test
# images have).
QML=$(command -v qml6 || command -v qml-qt6 || true)
[ -n "$QML" ] || fail "no qml tool (qml6 or qml-qt6) for the target window"
"${QML:-qml6}" "$OUT/target.qml" >"$OUT/target.log" 2>&1 &
TARGET=$!
sleep 4
read -r OX OY <<<"$(origin)"
info "the target's content starts at $OX,$OY"
[ -n "$OY" ] && pass "the target window is up" || fail "the target window was not found"
shot 00-target
images0=$(images)

# ---- 1. the first line
select_line 1
helper_done 30 && pass "1: the helper ended after the selection" || fail "1: the helper still runs"
shot 10-copied
got=$(clip)
[ "$got" = "$LINE1" ] && pass "1: Klipper's clipboard holds the selected line: \"$got\"" || fail "1: the clipboard holds \"$got\""
[ "$(notified "Text copied")" = 1 ] && pass "1: \"Text copied\" was notified" ||
  fail "1: notifications: $(grep -a 'string' "$OUT/notify-monitor.log" | head -8 | tr '\n' ' ')"
[ "$(images)" = "$images0" ] && [ -z "$(leftover)" ] && pass "1: no image is left (Pictures, the runtime directory)" ||
  fail "1: images $(images) (before $images0), left: $(leftover)"
[ -z "$(procs '^spectacle ')$(procs '/spectacle ')" ] && pass "1: no Spectacle keeps running" || fail "1: Spectacle runs: $(procs spectacle)"

# ---- 2. cancelled
before=$(clip)
pfinput 'key meta+shift+t'
sleep 5
pfinput 'key escape'
helper_done 15 && pass "2: Esc: the helper ends" || fail "2: the helper still runs after Esc"
[ "$(clip)" = "$before" ] && [ "$(notified "Text copied")" = 1 ] && [ "$(notified "No text found")" = 0 ] &&
  pass "2: Esc: nothing copied or notified" || fail "2: after Esc: clipboard \"$(clip)\", notifications $(notified "Text copied")"

# ---- 3. Spectacle's window open (no shot while it runs)
spectacle --launchonly >"$OUT/spectacle-open.log" 2>&1 &
sleep 5
qdbus | grep -qx ' *org.kde.spectacle' && [ "$(spectacle_windows)" = 1 ] &&
  pass "3: Spectacle is open (a window, org.kde.spectacle on the bus)" || fail "3: Spectacle is not open: $(spectacle_windows) windows"
select_line 2 return
helper_done 15 && pass "3: the helper handed over and ended" || fail "3: the helper still runs"
sleep 3
[ "$(clip)" = "$before" ] && [ "$(notified "Text copied")" = 1 ] &&
  pass "3: with Spectacle open the helper copies nothing itself" ||
  fail "3: clipboard \"$(clip)\", notifications $(notified "Text copied")"
[ -n "$(procs spectacle)" ] && [ "$(spectacle_windows)" = 1 ] &&
  pass "3: Spectacle keeps running and shows the new capture in its window (Extract Text there)" ||
  fail "3: Spectacle after the capture: processes $(procs spectacle | tr '\n' ' '), $(spectacle_windows) windows"
K windows >"$OUT/windows-step3.json" || true
for p in $(procs spectacle); do kill "$p" 2>/dev/null || true; done
sleep 2
shot 31-after-handover

# ---- 4. the second line
select_line 2
helper_done 30 && pass "4: the helper ended" || fail "4: the helper still runs"
shot 40-second
got=$(clip)
[ "$got" = "$LINE2" ] && pass "4: the clipboard follows: \"$got\"" || fail "4: the clipboard holds \"$got\""
[ "$(notified "Text copied")" = 2 ] && pass "4: a second \"Text copied\"" || fail "4: \"Text copied\" $(notified "Text copied") times"
qdbus org.kde.klipper /klipper org.kde.klipper.klipper.getClipboardHistoryMenu >"$OUT/klipper-history.txt" 2>&1 || true
grep -qxF "$LINE1" "$OUT/klipper-history.txt" && grep -qxF "$LINE2" "$OUT/klipper-history.txt" &&
  pass "4: Klipper's history keeps both lines" || info "4: Klipper's history: $(head -5 "$OUT/klipper-history.txt" | tr '\n' '|')"
[ "$(images)" = "$images0" ] && [ -z "$(leftover)" ] && pass "4: no image is left" || fail "4: images $(images), left: $(leftover)"

# ---- 5. quick settings' header button
pfinput 'key meta+a'
sleep 3
K windows >"$OUT/windows-qs.json" || true
# The pop-up's window (plasmashell's, at the top right); its header row: the 34 px round buttons
# 6 px apart, Copy Text the fourth from the right edge of the content (the frame's margin in).
read -r QX QY <<<"$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
pop = [w for w in d["windows"] if "plasmashell" in w["cls"] and not w["dock"] and not w["notification"]
       and not w["tooltip"] and 20 < w["geo"]["y"] < 200 and 300 < w["geo"]["w"] < 500]
g = max(pop, key=lambda w: w["geo"]["x"])["geo"] if pop else None
print("%d %d" % (g["x"] + g["w"] - int(sys.argv[2]) - 17 - 3 * 40, g["y"] + int(sys.argv[2]) + 17) if g else "")' "$OUT/windows-qs.json" "${QS_MARGIN:-16}")"
info "5: the pop-up's Copy Text button at ${QX:-?},${QY:-?}"
shot 50-qs
if [ -n "${QX:-}" ]; then
  pfinput "click $QX $QY"
  sleep 5
  y=$((OY + 200))
  pfinput "drag $((OX + 130)) $((y - 30)) $((OX + 820)) $((y + 70)) 20"
  helper_done 30 && pass "5: the helper ended" || fail "5: the helper still runs"
  shot 51-button
  got=$(clip)
  [ "$got" = "$LINE1" ] && pass "5: quick settings' button copies the selected line: \"$got\"" || fail "5: the clipboard holds \"$got\""
  [ "$(notified "Text copied")" = 3 ] && pass "5: a third \"Text copied\"" || fail "5: \"Text copied\" $(notified "Text copied") times"
else
  fail "5: the pop-up's window was not found"
fi

# ---- 6. the clipboard sheet's copy-text button (Popups board)
# Quick settings' dump (its debugAction dump:TAG): the summary ("..., sheet X,Y WxH" or "sheet
# closed") or the sheet's or the bar's targets ("name x,y wxh; ..."), PART summary|sheet|bar. The
# setup restarted the shell, which logs to the setup's state directory from then on.
qs_dump() {
  local tag=ct$RANDOM$RANDOM i line pattern
  local logs=("$OUT/plasmashell.log"
    "${XDG_STATE_HOME:-$HOME/.local/state}/plasma-fusion/plasmashell.log")
  qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
    "panels().forEach(function (p) {
       p.widgets('org.plasmafusion.quicksettings').forEach(function (w) {
         w.currentConfigGroup = ['General']; w.writeConfig('debugAction', 'dump:$tag'); }); });" \
    >/dev/null 2>&1 || true
  for ((i = 0; i < 30; i++)); do
    case $1 in
      sheet | bar) pattern="quicksettings: dump $tag $1: " ;;
      *) pattern="quicksettings: dump $tag: " ;;
    esac
    line=$(cat "${logs[@]}" 2>/dev/null | grep -a "$pattern" || true)
    line=${line##*$'\n'}
    [ -n "$line" ] && { echo "${line#*"dump $tag"}"; return 0; }
    sleep 0.3
  done
  return 1
}
pfinput 'key meta+v'
sleep 3
sheet=$(qs_dump sheet || true)
read -r CX CY <<<"$(tr ';' '\n' <<<"$sheet" |
  sed -n 's/^.*clipboardCopyText \([0-9-]*\),\([0-9-]*\) .*$/\1 \2/p' | head -1)"
info "6: the clipboard sheet's Copy Text button at ${CX:-?},${CY:-?}"
shot 60-sheet
if [ -n "${CX:-}" ]; then
  pfinput "click $CX $CY"
  sleep 5
  y=$((OY + 440))
  pfinput "drag $((OX + 130)) $((y - 30)) $((OX + 820)) $((y + 70)) 20"
  helper_done 30 && pass "6: the helper ended" || fail "6: the helper still runs"
  shot 61-sheet-button
  got=$(clip)
  [ "$got" = "$LINE2" ] && pass "6: the sheet's button copies the selected line: \"$got\"" ||
    fail "6: the clipboard holds \"$got\""
  [ "$(notified "Text copied")" = 4 ] && pass "6: a fourth \"Text copied\"" ||
    fail "6: \"Text copied\" $(notified "Text copied") times"
  summary=$(qs_dump summary || true)
  grep -q 'sheet closed' <<<"$summary" && pass "6: the sheet closed for the selection" ||
    fail "6: the sheet after the button: ${summary:0:160}"
else
  fail "6: no copy-text button in the clipboard sheet (${sheet:0:300})"
fi

# ---- 7. the top bar's copy-text button (Main board: before the clipboard button)
bar=$(qs_dump bar || true)
read -r BX BY <<<"$(tr ';' '\n' <<<"$bar" |
  sed -n 's/^.*copyTextBarButton \([0-9-]*\),\([0-9-]*\) .*$/\1 \2/p' | head -1)"
info "7: the top bar's Copy Text button at ${BX:-?},${BY:-?}"
shot 70-bar
if [ -n "${BX:-}" ]; then
  pfinput "click $BX $BY"
  sleep 5
  y=$((OY + 200))
  pfinput "drag $((OX + 130)) $((y - 30)) $((OX + 820)) $((y + 70)) 20"
  helper_done 30 && pass "7: the helper ended" || fail "7: the helper still runs"
  shot 71-bar-button
  got=$(clip)
  [ "$got" = "$LINE1" ] && pass "7: the top bar's button copies the selected line: \"$got\"" ||
    fail "7: the clipboard holds \"$got\""
  [ "$(notified "Text copied")" = 5 ] && pass "7: a fifth \"Text copied\"" ||
    fail "7: \"Text copied\" $(notified "Text copied") times"
else
  fail "7: no copy-text button in the top bar (${bar:0:300})"
fi

kill "$TARGET" "$MON" 2>/dev/null || true
grep -a 'string' "$OUT/notify-monitor.log" >"$OUT/notifications.txt" || true
info "done"
