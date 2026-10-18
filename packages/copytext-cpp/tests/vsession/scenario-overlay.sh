# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Copy text's own selection overlay (plasma-fusion-copytext-overlay, the CopyText board) in a
# private session: the real KWin, Tesseract and Klipper. The Fusion setup installs the helper and
# Meta+Shift+T; the overlay goes next to the helper with its desktop file (KWin allows it
# ScreenShot2 by that file) and its D-Bus service file, as the packages install it. A maximized
# window shows two known lines; then:
#   0. the first copy text: the session bus starts the overlay, which shows (the time from the
#      helper's start, the program's start included);
#   1. Meta+Shift+T: the helper hands over to the running overlay, which shows on the screen (its
#      own log: the pictures, then shown, in ms; KWin's window list); a drag around the first line,
#      released: Klipper holds the line, "Text copied" is notified, the overlay is gone;
#   2. Meta+Shift+T, Esc: nothing copied or notified, the overlay gone;
#   3. three more hand-overs for the timings; 4. from the helper itself: the overlay against
#      Spectacle's selection; the overlay's memory after each use and its CPU while it waits.
# Run: tools/vsession/remote.sh ov-1 packages/copytext-cpp/tests/vsession/scenario-overlay.sh SEED
# (SEED: the stage in ~/pf-stage, tools/ in ~/pf-tools, the built overlay in ~/pf-overlay).
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
clip() { qdbus org.kde.klipper /klipper org.kde.klipper.klipper.getClipboardContents 2>/dev/null || true; }
notified() { grep -c "string \"$1\"" "$OUT/notify-monitor.log" || true; }
LINE1="Plasma Fusion copies 4812 words"
LINE2="Second line from the screen 2026"
# The overlay's windows in KWin's list (layer-shell surfaces of its process).
overlay_windows() {
  K run "var l = workspace.windowList(), n = 0; for (var i = 0; i < l.length; ++i) {
    if (String(l[i].resourceClass).indexOf('copytextoverlay') >= 0) { n++; } } report(n);"
}
# Processes of this session whose command line holds PATTERN (the host's own session is left alone).
procs() {
  local p
  for p in /proc/[0-9]*; do
    tr '\0' ' ' <"$p/cmdline" 2>/dev/null | grep -q -- "$1" || continue
    grep -qz "^XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR\$" "$p/environ" 2>/dev/null && echo "${p#/proc/}"
  done
  return 0
}
wait_log() { # PATTERN SECONDS: the overlay's log has PATTERN (a new line after $marks lines)
  local end=$((SECONDS + $2))
  while [ "$SECONDS" -lt "$end" ]; do
    tail -n +"$((marks + 1))" "$OUT/overlay.log" | grep -q "$1" && return 0
    sleep 0.1
  done
  return 1
}

# ---- the setup, then the overlay next to the helper
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || info "fusion-config rc=$?"
DIR=$HOME/.local/libexec/plasma-fusion
install -m 0755 "$HOME/pf-overlay/plasma-fusion-copytext-overlay" "$DIR/"
mkdir -p "$HOME/.local/share/applications"
sed "s#@PF_HELPER_DIR@#$(readlink -f "$DIR")#" "$HOME/pf-overlay/org.plasmafusion.copytextoverlay.desktop.in" \
  >"$HOME/.local/share/applications/org.plasmafusion.copytextoverlay.desktop"
kbuildsycoca6 >/dev/null 2>&1 || true
# PFV_OVERLAY_ENV in the seed's pf-overlay/env (for example QT_QUICK_BACKEND=software): a variant.
OVERLAY_ENV=()
[ ! -s "$HOME/pf-overlay/env" ] || read -r -a OVERLAY_ENV <"$HOME/pf-overlay/env"
info "the overlay's environment: ${OVERLAY_ENV[*]:-(none)}"
# Started by the session bus on the first copy text, as the packages install it (its D-Bus service
# file); its output into the overlay's log here. The program is exec'ed, so KWin finds it.
: >"$OUT/overlay.log"
mkdir -p "$HOME/.local/share/dbus-1/services"
cat >"$HOME/.local/share/dbus-1/services/org.plasmafusion.CopyTextOverlay.service" <<SERVICE
[D-BUS Service]
Name=org.plasmafusion.CopyTextOverlay
Exec=/bin/sh -c 'exec env ${OVERLAY_ENV[*]} $(readlink -f "$DIR")/plasma-fusion-copytext-overlay >>$OUT/overlay.log 2>&1'
SERVICE
dbus-send --session --dest=org.freedesktop.DBus --type=method_call /org/freedesktop/DBus org.freedesktop.DBus.ReloadConfig
sleep 1
overlay_pid() { pgrep -n -f "$(readlink -f "$DIR")/plasma-fusion-copytext-overlay" || true; }
[ -z "$(overlay_pid)" ] && pass "before the first copy text the overlay does not run" || fail "the overlay runs before it is used"

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
QML=$(command -v qml6 || command -v qml-qt6 || true)
"${QML:-qml6}" "$OUT/target.qml" >"$OUT/target.log" 2>&1 &
TARGET=$!
sleep 4
read -r OX OY <<<"$(K run "var l = workspace.windowList(), r = ''; for (var i = 0; i < l.length; ++i) {
  if (String(l[i].caption) === 'copytext-target') { var g = l[i].clientGeometry; r = Math.round(g.x) + ' ' + Math.round(g.y); } }
  report(r);" | python3 -c 'import json, sys; print(json.load(sys.stdin))')"
info "the target's content starts at $OX,$OY"
shot 00-target

# ---- 0. the first copy text: the session bus starts the overlay (the helper's Start() call)
marks=0
t0=$(date +%s%3N)
# In the background with a limit: without the overlay the helper would go on to Spectacle's
# selection, which waits for a person.
timeout 30 "$DIR/plasma-fusion-copytext" >/dev/null 2>&1 &
if wait_log "shown in" 10; then
  pass "0: the first copy text starts the overlay, which shows"
else
  fail "0: no overlay: $(tr '\n' ' ' <"$OUT/overlay.log")"
  for p in $(procs plasma-fusion-copytext) $(procs spectacle); do kill "$p" 2>/dev/null || true; done
fi
at=$(sed -n 's/.*shown in .* ms at \([0-9]*\).*/\1/p' "$OUT/overlay.log" | head -1)
info "0: the overlay $(( ${at:-0} - t0 )) ms after the helper started, the program's start included"
OVL=$(overlay_pid)
qdbus | grep -qx ' *org.plasmafusion.CopyTextOverlay' && [ -n "$OVL" ] && pass "0: it waits on the session bus (pid $OVL)" || fail "0: not on the bus"
sleep 0.4
pfinput 'key escape'
sleep 1.5

# ---- 1. hand-over, the box, released
marks=$(wc -l <"$OUT/overlay.log")
pfinput 'key meta+shift+t'
wait_log "shown in" 5 && pass "1: Meta+Shift+T: the overlay shows ($(tail -n +"$((marks + 1))" "$OUT/overlay.log" | tr '\n' ' '))" ||
  fail "1: no overlay: $(tail -n +"$((marks + 1))" "$OUT/overlay.log" | tr '\n' ' ')"
sleep 0.5
info "1: overlay windows in KWin's list: $(overlay_windows)"
shot 10-overlay
y=$((OY + 200))
pfinput "drag $((OX + 130)) $((y - 30)) $((OX + 820)) $((y + 70)) 20"
for _ in $(seq 1 50); do [ "$(clip)" = "$LINE1" ] && break; sleep 0.2; done
got=$(clip)
[ "$got" = "$LINE1" ] && pass "1: released: Klipper holds the line: \"$got\"" || fail "1: the clipboard holds \"$got\""
sleep 1
[ "$(notified "Text copied")" = 1 ] && pass "1: \"Text copied\" was notified" || fail "1: \"Text copied\" $(notified "Text copied") times"
wait_log "closed" 3 && pass "1: the overlay is gone (its log; KWin's list: $(overlay_windows) windows)" ||
  fail "1: the overlay did not close: $(tail -n +"$((marks + 1))" "$OUT/overlay.log" | tr '\n' ' ')"
shot 11-after

# ---- 2. Esc
before=$(clip)
marks=$(wc -l <"$OUT/overlay.log")
pfinput 'key meta+shift+t'
wait_log "shown in" 5 || true
sleep 0.5
pfinput 'key escape'
sleep 1.5
wait_log "closed" 3 && [ "$(clip)" = "$before" ] && [ "$(notified "Text copied")" = 1 ] && [ "$(notified "No text found")" = 0 ] &&
  pass "2: Esc: the overlay gone, nothing copied or notified" ||
  fail "2: after Esc: $(tail -n +"$((marks + 1))" "$OUT/overlay.log" | tr '\n' ' '), clipboard \"$(clip)\""

# ---- 3. timings, then the overlay's cost while it waits
for n in 1 2 3; do
  marks=$(wc -l <"$OUT/overlay.log")
  pfinput 'key meta+shift+t'
  wait_log "shown in" 5 || true
  info "3.$n: $(tail -n +"$((marks + 1))" "$OUT/overlay.log" | tr '\n' ' ')"
  sleep 0.4
  pfinput 'key escape'
  sleep 1.2
done
# ---- 4. the same from the helper itself, against Spectacle's selection (the helper's way back
# without the overlay): from the helper's start to the overlay shown (its log, ms since the epoch)
# or to Spectacle's selection window (a KWin script's windowAdded, in KWin's log).
cat >"$OUT/added.js" <<'JS'
workspace.windowAdded.connect(w => console.warn("PFT added " + Date.now() + " " + w.resourceClass));
JS
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$OUT/added.js" pfadded >/dev/null
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1
for n in 1 2 3; do
  marks=$(wc -l <"$OUT/overlay.log")
  t0=$(date +%s%3N)
  "$DIR/plasma-fusion-copytext" >/dev/null 2>&1
  wait_log "shown in" 5 || true
  at=$(tail -n +"$((marks + 1))" "$OUT/overlay.log" | sed -n 's/.*shown in .* ms at \([0-9]*\).*/\1/p' | head -1)
  info "4.$n: the overlay $(( ${at:-0} - t0 )) ms after the helper started"
  sleep 0.4
  pfinput 'key escape'
  sleep 1.5
done
for n in 1 2; do
  k=$(grep -ac "PFT added" "$OUT/kwin.log" || true)
  t0=$(date +%s%3N)
  PLASMA_FUSION_COPYTEXT_NO_OVERLAY=1 "$DIR/plasma-fusion-copytext" >/dev/null 2>&1 &
  at=
  for _ in $(seq 1 100); do
    at=$({ grep -a "PFT added" "$OUT/kwin.log" || true; } | tail -n +"$((k + 1))" | { grep -a "spectacle" || true; } | head -1 |
      sed 's/.*PFT added \([0-9]*\).*/\1/')
    [ -n "$at" ] && break
    sleep 0.1
  done
  info "4.$n: Spectacle's selection $(( ${at:-0} - t0 )) ms after the helper started"
  sleep 1
  pfinput 'key escape'
  sleep 3
done
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript pfadded >/dev/null 2>&1 || true
info "4: the overlay's memory after each use: $(grep -a 'waiting,' "$OUT/overlay.log" | sed 's/.*waiting, //' | tr '\n' ' ')"

sleep 3
read -r _ _ _ _ _ _ _ _ _ _ _ _ _ u1 s1 _ <"/proc/$OVL/stat"
sleep 10
read -r _ _ _ _ _ _ _ _ _ _ _ _ _ u2 s2 _ <"/proc/$OVL/stat"
ticks=$(getconf CLK_TCK)
info "3: waiting: RSS $(awk '/^VmRSS/ {print $2 " kB"}' "/proc/$OVL/status"), CPU $(( (u2 + s2 - u1 - s1) * 1000 / ticks )) ms in 10 s"

kill "$TARGET" "$MON" "$OVL" 2>/dev/null || true
grep -a 'string' "$OUT/notify-monitor.log" >"$OUT/notifications.txt" || true
info "done"
trap - ERR
set +e
[ "$(grep -c '^FAIL' "$OUT/checks.txt" || true)" = 0 ]
