# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Rubber-band selection cost with many desktop icons (BACKLOG S5), sourced inside a tools/vsession
# session started with PFV_CWD=out and KWIN_LOG_PERFORMANCE_DATA=1 (band.sh). Installs Plasma Fusion,
# makes the primary desktop a Folder View with the BACKLOG M1 settings unless the layout already
# does, then for 20, 60 and 100 files on ~/Desktop sweeps a selection band from the empty
# bottom-right corner of the icon area to its top-left corner in 3 s with real pointer input.
# pfstat.py snapshots bracket each sweep (band-N-0, band-N-1), marks bracket the input.
# shellcheck shell=bash
exec 2>&1
export OUT KWIN_PID=$PPID PFINPUT_MARKS=$OUT/marks.jsonl
T=$HOME/pf-tools/tests
P() { python3 "$PFV/pfinput.py" "$@" >>"$OUT/pfinput.log" 2>&1; }
S() { python3 "$T/perf/pfstat.py" "$1"; }
M() { python3 -c 'import json,time,sys; open(sys.argv[1],"a").write(json.dumps({"mark":sys.argv[2],"epoch":time.time(),"mono":time.monotonic()})+"\n")' "$PFINPUT_MARKS" "$1"; }
log() { echo "[$(date +%T)] $*" >>"$OUT/steps.log"; }
echo "arm=fusion kwin=$KWIN_PID" >"$OUT/arm.txt"
M begin
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fusion-config.log" 2>&1
echo "fusion-config rc=$?" >>"$OUT/fusion-config.log"
mkdir -p "$HOME/Desktop"
find "$HOME/Desktop" -mindepth 1 -maxdepth 1 ! -name .directory -delete
# Folder View on the primary desktop unless the layout already made it one.
read -r CID PLUGIN < <(evaljs - <<'JS'
var ds = desktops();
for (var i = 0; i < ds.length; ++i) if (ds[i].screen === 0) print(ds[i].id + " " + ds[i].type);
JS
)
kquitapp6 plasmashell >/dev/null 2>&1; sleep 2
A=plasma-org.kde.plasma.desktop-appletsrc
log "primary desktop containment $CID plugin $PLUGIN"
if [ "$PLUGIN" != org.kde.plasma.folder ]; then
  kwriteconfig6 --file "$A" --group Containments --group "$CID" --key plugin org.kde.plasma.folder
  for kv in url=desktop:/ sortMode=-1 arrangement=1 alignment=0 iconSize=2 labelWidth=1 textLines=2 \
            previews=true popups=false toolTips=false selectionMarkers=true useTypeAhead=true locked=false; do
    kwriteconfig6 --file "$A" --group Containments --group "$CID" --group General --key "${kv%%=*}" "${kv#*=}"
  done
  echo "folderview=switched-by-test" >>"$OUT/arm.txt"
else
  echo "folderview=from-layout" >>"$OUT/arm.txt"
fi
plasmashell >>"$OUT/plasmashell2.log" 2>&1 &
wait_for_name org.kde.plasmashell
qdbus org.kde.KWin /KWin reconfigure
sleep 15
# The icon area: Plasma's available rect of the first output.
read -r AX AY AW AH < <(python3 - <<'PY'
from gi.repository import Gio, GLib
b = Gio.bus_get_sync(Gio.BusType.SESSION, None)
try:
    r = b.call_sync("org.kde.plasmashell", "/StrutManager", "org.kde.PlasmaShell.StrutManager", "availableScreenRect",
                    GLib.Variant("(i)", (0,)), None, Gio.DBusCallFlags.NONE, 5000, None)
    print(*[int(v) for v in r.unpack()[0]])
except GLib.Error:
    print(0, 34, 1440, 762)
PY
)
X1=$((AX + AW - 40)); Y1=$((AY + AH - 40)); X2=$((AX + 12)); Y2=$((AY + 12))
echo "area=$AX,$AY,${AW}x$AH band=$X1,$Y1..$X2,$Y2" >>"$OUT/arm.txt"
P "move $((AX + AW / 2)) $((AY + AH - 20))" 'sleep 1'
for n in 20 60 100; do
  find "$HOME/Desktop" -mindepth 1 -maxdepth 1 ! -name .directory -delete
  for i in $(seq -w 1 "$n"); do echo "band test $i" >"$HOME/Desktop/band$i.txt"; done
  sleep 8
  shot "band-$n-icons"
  P "move $X1 $Y1" 'sleep 1'
  S "band-$n-0"; M "band-$n-0"
  # press, 150 steps 20 ms apart (3 s), release: a selection band over every icon
  P "drag $X1 $Y1 $X2 $Y2 150 0.02 0 0.3"
  M "band-$n-1"; S "band-$n-1"
  shot "band-$n-after"
  P 'key esc' "click $X1 $Y1" 'sleep 1'
  sleep 3
done
M end
qdbus org.kde.KWin /KWin supportInformation >"$OUT/kwin-support-end.txt" 2>&1
