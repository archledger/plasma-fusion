#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Real hover/click parity and mute actions, on a private virtual microphone only.
# Seed HOME/pf-stage and HOME/pf-tools. Run with tools/vsession/vsession.sh.
set -euo pipefail
export QT_LOGGING_RULES=org.plasmafusion.livechips.debug=true
export PIPEWIRE_RUNTIME_DIR=$XDG_RUNTIME_DIR
export PULSE_SERVER=unix:$XDG_RUNTIME_DIR/pulse/native
CHK=$OUT/checks.txt
PLOG=$OUT/plasmashell.log
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
trap 'fail "scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
last() { grep -a "livechips: $1" "$PLOG" | tail -1 | sed "s/.*livechips: $1 //"; }
wait_log() {
    for _ in $(seq 1 40); do
        grep -aqE "livechips: $1" "$PLOG" && return 0
        sleep 0.25
    done
    return 1
}
chip() {
    last 'chips at' | tr ';' '\n' | awk '$1 == "capsule" {
        split($2,p,","); split($3,s,"x"); printf "%d %d\n",p[1]+s[1]/2,p[2]+s[2]/2 }'
}
hover_button() {
    last 'hover panel' | tr ';' '\n' | grep -F "\"$1\" at" | head -1 | sed 's/.* at //; s/,/ /'
}
stream_muted() {
    for _ in $(seq 1 20); do
        if pactl --format=json list source-outputs | python3 -c '
import json, sys
streams = [s for s in json.load(sys.stdin) if s["properties"].get("application.name") == "Sound Recorder"]
sys.exit(0 if len(streams) == 1 and streams[0]["mute"] == (sys.argv[1] == "yes") else 1)
' "$1"; then return 0; fi
        sleep 0.1
    done
    return 1
}

# No session manager is started: there are no real audio devices in this graph.
pipewire >"$OUT/pipewire.log" 2>&1 &
for _ in $(seq 1 40); do
    [ ! -S "$XDG_RUNTIME_DIR/pipewire-0" ] || break
    sleep 0.25
done
pipewire-pulse >"$OUT/pipewire-pulse.log" 2>&1 &
for _ in $(seq 1 40); do
    [ ! -S "$XDG_RUNTIME_DIR/pulse/native" ] || break
    sleep 0.25
done
pactl load-module module-null-sink media.class=Audio/Source/Virtual sink_name=fakemic >"$OUT/virtual-source.log"
sources=
for _ in $(seq 1 40); do
    sources=$(pactl list short sources)
    if grep -q fakemic <<<"$sources"; then break; fi
    sleep 0.1
done
printf 'INFO private sources: %s\n' "$sources" >>"$CHK"
source_names=$(awk '{print $2}' <<<"$sources")
# pipewire-pulse also creates its default silent output's virtual monitor.
if grep -qx fakemic <<<"$source_names" &&
    ! grep -vxF -e fakemic -e auto_null.monitor <<<"$source_names" | grep -q .; then
    pass "only the private virtual audio sources exist"
else
    fail "unexpected audio graph"
    exit 1
fi
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/setup.log" 2>&1
pfv_restart_shell 10
parecord --raw --device=fakemic --client-name='Sound Recorder' \
    --property='application.name=Sound Recorder' /dev/null >"$OUT/parecord.log" 2>&1 &
recorder=$!
wait_log 'state .*"capsule":\[[^]]*"microphone"'
wait_log 'chips at .*capsule '
read -r cx cy <<<"$(chip)"
pfinput "move $cx 450"
pfinput "move $cx $cy"
wait_log 'hover panel .*microphone "Sound Recorder" "Mute"'
pass "hover names Sound Recorder and its microphone action"
shot 10-hover

read -r mx my <<<"$(hover_button Mute)"
pfinput "click $mx $my"
wait_log 'hover panel .*microphone "Sound Recorder" "Unmute"'
if stream_muted yes; then pass "hover Mute reaches the app stream"; else fail "hover did not mute"; fi
read -r mx my <<<"$(hover_button Unmute)"
pfinput "click $mx $my"
if stream_muted no; then pass "hover Unmute restores the app stream"; else fail "hover did not unmute"; fi

pfinput "click $cx $cy"
wait_log 'panel .*microphone "Sound Recorder" "Mute"'
pass "click names the same app and resource"
shot 20-click
kill "$recorder"
wait "$recorder" || true
for _ in $(seq 1 40); do
    if ! last state | grep -q microphone; then break; fi
    sleep 0.25
done
if ! last state | grep -q microphone; then pass "stopping the stream clears the indicator"; else fail "stale microphone indicator"; fi
pfinput 'key escape'
trap - ERR
set +e
[ "$(grep -c '^FAIL' "$CHK" || true)" = 0 ]
