#!/bin/bash
# Run an isolated, headless Plasma session on this machine and execute a scenario in it.
#
#   vsession.sh NAME SCENARIO [WIDTHxHEIGHT] [TIMEOUT_SECONDS]
#
# Everything lives under /tmp/pfv-NAME: home/ (the session's HOME; pre-seed it before the run),
# run/ (XDG_RUNTIME_DIR), out/ (screenshots and logs). The session has its own D-Bus session bus,
# its own Wayland socket and never touches the logged-in desktop.
#
# The scenario is a bash file sourced inside the session. It can use:
#   shot NAME            screenshot of the whole virtual screen -> out/NAME.png
#   wait_for_name NAME   wait (max 20 s) until a D-Bus name appears on the session bus
#   qdbus ...            qdbus-qt6 on the session bus
#   evaljs FILE|-        run a plasmashell desktop scripting snippet (org.kde.PlasmaShell.evaluateScript)
#   $OUT $HOME $PFV      output dir, session HOME, run root
# Set NO_PLASMASHELL=1 in the scenario's environment to start only KWin.
set -u
NAME=${1:?name}; SCENARIO=${2:?scenario}; SIZE=${3:-1440x900}; TMO=${4:-240}
PFV=/tmp/pfv-$NAME
W=${SIZE%x*}; H=${SIZE#*x}
mkdir -p "$PFV/home/.config" "$PFV/run" "$PFV/out"
chmod 700 "$PFV/run"
# Plasma Welcome would open on first start; mark this version as seen.
[ -e "$PFV/home/.config/plasma-welcomerc" ] || printf '[General]\nLastSeenVersion=6.7.5\nShowUpdatePage=false\n' >"$PFV/home/.config/plasma-welcomerc"
rm -rf "$PFV/run/"* "$PFV/out/"*
cp "$SCENARIO" "$PFV/scenario.sh"

cat > "$PFV/inner.sh" <<'INNER'
#!/bin/bash
set -u
OUT=$PFV/out
shot() { spectacle -b -n -f -o "$OUT/$1.png" >>"$OUT/spectacle.log" 2>&1 || echo "shot $1 failed" >>"$OUT/errors.log"; }
qdbus() { qdbus-qt6 "$@"; }
wait_for_name() { for _ in $(seq 1 40); do qdbus-qt6 | grep -qx " *$1" && return 0; sleep 0.5; done; echo "timeout waiting for $1" >>"$OUT/errors.log"; return 1; }
evaljs() { local js; if [ "$1" = - ]; then js=$(cat); else js=$(cat "$1"); fi; qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$js"; }
export -f shot qdbus wait_for_name evaljs
cleanup() { kill $(jobs -p) 2>/dev/null; sleep 1; kill -9 $(jobs -p) 2>/dev/null; }
trap cleanup EXIT
fc-cache -f >/dev/null 2>&1
/usr/libexec/kactivitymanagerd >"$OUT/kamd.log" 2>&1 &
kded6 >"$OUT/kded.log" 2>&1 &
sleep 2
if [ "${NO_PLASMASHELL:-0}" != 1 ]; then
  plasmashell >"$OUT/plasmashell.log" 2>&1 &
  wait_for_name org.kde.plasmashell
  sleep 8
  # First-run "Welcome to Plasma" window: close it so it does not cover screenshots.
  for p in /proc/[0-9]*; do
    [ "$(cat "$p/comm" 2>/dev/null)" = plasma-welcome ] || continue
    grep -qz "^XDG_RUNTIME_DIR=$PFV/run\$" "$p/environ" 2>/dev/null && kill "${p#/proc/}"
  done
fi
qdbus-qt6 org.kde.KWin /KWin supportInformation >"$OUT/kwin-support.txt" 2>&1
source "$PFV/scenario.sh" >"$OUT/scenario.log" 2>&1
echo "scenario rc=$?" >>"$OUT/scenario.log"
INNER
chmod +x "$PFV/inner.sh"

env -i HOME="$PFV/home" XDG_RUNTIME_DIR="$PFV/run" PFV="$PFV" NO_PLASMASHELL="${NO_PLASMASHELL:-0}" \
  PATH=/usr/bin:/bin:/usr/lib64/qt6/bin LANG=en_US.UTF-8 \
  XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=KDE KDE_FULL_SESSION=true KDE_SESSION_VERSION=6 \
  QT_QPA_PLATFORM=wayland \
  timeout "$TMO" dbus-run-session -- kwin_wayland --virtual --width "$W" --height "$H" \
    --socket "pfv-$NAME" --no-lockscreen --exit-with-session "$PFV/inner.sh" >"$PFV/out/kwin.log" 2>&1
echo "session rc=$?" >>"$PFV/out/scenario.log"

# Kill anything that still belongs to this session (matched by its private runtime dir).
for p in /proc/[0-9]*; do
  grep -qz "^XDG_RUNTIME_DIR=$PFV/run\$" "$p/environ" 2>/dev/null && kill -9 "${p#/proc/}" 2>/dev/null
done
grep -E -i "compositing type|OpenGL renderer|OpenGL version|blur" "$PFV/out/kwin-support.txt" 2>/dev/null | head -5 >"$PFV/out/compositor.txt"
ls "$PFV/out"
