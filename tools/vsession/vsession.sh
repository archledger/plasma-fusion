#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Run an isolated, headless Plasma session on this machine and execute a scenario in it.
#
#   vsession.sh NAME SCENARIO [WIDTHxHEIGHT] [TIMEOUT_SECONDS]
#
# WIDTHxHEIGHT is the size of each virtual output in device pixels. PFV_SCALE (default 1, e.g. 1.25,
# 1.333333, 2; applied with kscreen-doctor before plasmashell starts) and PFV_OUTPUTS (default 1:
# several outputs side by side) emulate other displays.
#
# Everything lives under /var/tmp/pfv-NAME (PFV_BASE overrides /var/tmp): home/ (the session's HOME; pre-seed it before the run),
# run/ (XDG_RUNTIME_DIR), out/ (screenshots and logs). The session has its own D-Bus session bus,
# its own Wayland socket and never touches the logged-in desktop.
#
# The scenario is a bash file sourced inside the session. It can use:
#   shot NAME            screenshot of the whole virtual screen -> out/NAME.png
#   wait_for_name NAME   wait (max 20 s) until a D-Bus name appears on the session bus
#   qdbus ...            qdbus-qt6 on the session bus
#   evaljs FILE|-        run a plasmashell desktop scripting snippet (org.kde.PlasmaShell.evaluateScript)
#   pfinput CMD...       real pointer/keyboard input through KWin EIS, e.g.
#                        pfinput 'move 100 20' 'click 1300 17' 'key meta' 'key ctrl+alt+t'
#                        'drag X1 Y1 X2 Y2' 'scroll X Y STEPS' 'sleep 0.5' (see pfinput.py)
#   $OUT $HOME $PFV      output dir, session HOME, run root
# Extra variables for the whole session (e.g. QT_PLUGIN_PATH): KEY=VALUE lines in home/.config/pfv-env.
# The session environment matches startplasma where it matters: XDG_CONFIG_DIRS starts with
# ~/.config/kdedefaults (where a Global Theme writes its defaults) and Qt logs to stderr.
# Set NO_PLASMASHELL=1 in the scenario's environment to start only KWin.
#
# Optional switches (environment of this script; unset = no change to the session):
#   PFV_TABLET=on|off|auto  kwinrc [Input] TabletMode, written into the HOME before KWin starts
#   PFV_ANIM=FACTOR         kdeglobals [KDE] AnimationDurationFactor (0 = no animations, 1 = normal)
#   PFV_FONT_PT=PT          kdeglobals [General] font, menuFont, toolBarFont at PT points (family
#                           kept); fusion-config.sh --install sets the Fusion fonts on its first
#                           run, so after it use the pfv_font helper instead
#   PFV_LANGUAGE=LIST       LANGUAGE for the whole session (e.g. ar for right-to-left)
#   PFV_SHELL=PATH          SHELL for the whole session (e.g. /bin/bash; Konsole warns without it)
#   PFV_CWD=DIR             working directory of the session, relative to the run root (e.g. out:
#                           KWin writes its KWIN_LOG_PERFORMANCE_DATA CSV there, and out/ is fetched)
#   PFV_KDE_PROFILE=1       append /usr/share/kde-settings/kde-profile/default/xdg to XDG_CONFIG_DIRS,
#                           as Fedora's Plasma session does (its kwinrc starts plasma-keyboard as the
#                           input method)
#   PFV_XWAYLAND=1          KWin with Xwayland (X11 clients; DISPLAY also reaches the private bus)
#   PFV_LOCK=1              a lock-capable session: KWin without --no-lockscreen; pfv_lock locks it.
#                           Never type a password into its lock screen: pam_faillock counts failures
#                           against the host user. pfinput refuses Return, Enter and 'type' while the
#                           screen is locked. The locker's own idle timeout applies (kscreenlockerrc).
# Extra scenario helpers: pfv_font PT, pfv_anim FACTOR, pfv_tablet on|off|auto (write the setting
# and notify the running session), pfv_restart_shell (quit plasmashell, start it again, wait),
# pfv_rotate [OUTPUT] normal|left|right|inverted (kscreen-doctor inside the session; default the
# first output), pfv_lock (lock-capable sessions only).
#
# Teardown: when the scenario ends, or at TIMEOUT (the scenario shell then gets SIGTERM; a hard
# stop follows 30 s later), every process of the session except KWin's own (the processes that
# started KWin, the bus daemon, KWin's children such as Xwayland) gets SIGTERM while KWin still
# runs, SIGKILL after 5 s, and the sweep repeats for services the bus started meanwhile. A Qt
# service started after KWin had gone aborts with a core dump: the portal frontend re-activated
# xdg-desktop-portal-kde that way. out/teardown.log lists what was stopped.
set -u
NAME=${1:?name}; SCENARIO=${2:?scenario}; SIZE=${3:-1440x900}; TMO=${4:-240}
# Sessions live on disk (/var/tmp): a HOME with the Fusion stage holds ~25k files, and /tmp is a
# tmpfs with a fixed inode count that the logged-in user needs too.
PFV=${PFV_BASE:-/var/tmp}/pfv-$NAME
W=${SIZE%x*}; H=${SIZE#*x}
mkdir -p "$PFV/home/.config" "$PFV/run" "$PFV/out"
chmod 700 "$PFV/run"
# Services that must not run in a test session: KDE Connect would announce a second device on
# the network. The private bus reads ~/.local/share/dbus-1/services first, so a stub wins.
mkdir -p "$PFV/home/.local/share/dbus-1/services"
# shellcheck disable=SC2043  # one service today; the list is meant to grow
for svc in org.kde.kdeconnect; do
  printf '[D-BUS Service]\nName=%s\nExec=/bin/false\n' "$svc" >"$PFV/home/.local/share/dbus-1/services/$svc.service"
done
# Plasma Welcome would open on first start; mark this version as seen.
[ -e "$PFV/home/.config/plasma-welcomerc" ] || printf '[General]\nLastSeenVersion=6.7.5\nShowUpdatePage=false\n' >"$PFV/home/.config/plasma-welcomerc"
# Configuration search path of the session (Fedora adds its kde-profile layer; PFV_KDE_PROFILE).
CONFIG_DIRS="$PFV/home/.config/kdedefaults:/etc/xdg"
[ "${PFV_KDE_PROFILE:-0}" = 1 ] && CONFIG_DIRS+=":/usr/share/kde-settings/kde-profile/default/xdg"
# Optional switches (see the header). kwriteconfig6 only edits files; offscreen keeps Qt away
# from any display.
pfv_kwc() { QT_QPA_PLATFORM=offscreen kwriteconfig6 --file "$PFV/home/.config/$1" --group "$2" --key "$3" "$4"; }
[ -n "${PFV_TABLET:-}" ] && pfv_kwc kwinrc Input TabletMode "$PFV_TABLET"
[ -n "${PFV_ANIM:-}" ] && pfv_kwc kdeglobals KDE AnimationDurationFactor "$PFV_ANIM"
if [ -n "${PFV_FONT_PT:-}" ]; then
  # the family as the session will see it (a Global Theme's kdedefaults layer included)
  fam=$(QT_QPA_PLATFORM=offscreen XDG_CONFIG_HOME="$PFV/home/.config" XDG_CONFIG_DIRS="$CONFIG_DIRS" \
    kreadconfig6 --file kdeglobals --group General --key font --default "Noto Sans,10")
  for k in font menuFont toolBarFont; do
    pfv_kwc kdeglobals General "$k" "${fam%%,*},$PFV_FONT_PT,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
  done
fi
rm -rf "$PFV/run/"* "$PFV/out/"*
cp "$SCENARIO" "$PFV/scenario.sh"
HERE=$(cd "$(dirname "$0")" && pwd)
PFINPUT_SRC=${PFINPUT:-$HERE/pfinput.py}
[ -f "$PFINPUT_SRC" ] && cp "$PFINPUT_SRC" "$PFV/pfinput.py"

cat > "$PFV/inner.sh" <<'INNER'
#!/bin/bash
set -u
OUT=$PFV/out
shot() { spectacle -b -n -f -o "$OUT/$1.png" >>"$OUT/spectacle.log" 2>&1 || echo "shot $1 failed" >>"$OUT/errors.log"; }
qdbus() { qdbus-qt6 "$@"; }
wait_for_name() { for _ in $(seq 1 40); do qdbus-qt6 | grep -qx " *$1" && return 0; sleep 0.5; done; echo "timeout waiting for $1" >>"$OUT/errors.log"; return 1; }
evaljs() { local js; if [ "$1" = - ]; then js=$(cat); else js=$(cat "$1"); fi; qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$js"; }
pfinput() { python3 "$PFV/pfinput.py" "$@" >>"$OUT/pfinput.log" 2>&1; }
export -f shot qdbus wait_for_name evaljs pfinput
# Settings switches for a running session (they notify KWin and Plasma like System Settings does).
pfv_font() {
  local fam k; fam=$(kreadconfig6 --file kdeglobals --group General --key font --default "Noto Sans,10")
  for k in font menuFont toolBarFont; do
    kwriteconfig6 --file kdeglobals --group General --key "$k" --notify "${fam%%,*},$1,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
  done
}
pfv_anim() { kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor --notify "$1"; }
pfv_tablet() { kwriteconfig6 --file kwinrc --group Input --key TabletMode --notify "$1"; }
pfv_restart_shell() {
  kquitapp6 plasmashell >/dev/null 2>&1; sleep 2
  plasmashell >>"$OUT/plasmashell.log" 2>&1 &
  wait_for_name org.kde.plasmashell; sleep "${1:-8}"
}
# Rotate an output inside this session (the M2 portrait step, tablet rotation tests).
pfv_rotate() {  # [OUTPUT] normal|left|right|inverted
  local o r
  if [ $# -ge 2 ]; then o=$1; r=$2; else
    r=${1:?pfv_rotate: normal, left, right or inverted}
    o=$(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '/^Output:/{print $3; exit}')
  fi
  kscreen-doctor "output.$o.rotation.$r" >>"$OUT/kscreen-doctor.log" 2>&1 || echo "pfv_rotate $o $r failed" >>"$OUT/errors.log"
  sleep 1
}
# Lock the screen (PFV_LOCK=1 sessions only); waits until the locker reports it is active.
pfv_lock() {
  qdbus-qt6 org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.Lock >/dev/null 2>&1
  for _ in $(seq 1 20); do
    [ "$(qdbus-qt6 org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.GetActive 2>/dev/null)" = true ] && return 0
    sleep 0.25
  done
  echo "pfv_lock: the screen did not lock (PFV_LOCK=1 not set?)" >>"$OUT/errors.log"; return 1
}
# (not exported: the scenario is sourced by this shell, and exported functions would add variables
# to the environment of every program the session starts)
# Teardown (see the header). Only shell builtins look at /proc here, so the sweep never meets its
# own helpers.
pfv_alive() { local st; read -r st 2>/dev/null <"/proc/$1/stat" || return 1; st=${st##*) }; [ "${st%% *}" != Z ]; }
pfv_pids() {  # PFV_PIDS := this session's processes except PFV_KEEP and their children (not ours)
  local p pid e st mine
  PFV_PIDS=()
  for p in /proc/[0-9]*; do
    pid=${p#/proc/}
    [[ " $PFV_KEEP " == *" $pid "* ]] && continue
    mapfile -d '' -t e 2>/dev/null <"$p/environ" || continue
    mine=0
    for st in "${e[@]}"; do [ "$st" = "XDG_RUNTIME_DIR=$PFV/run" ] && { mine=1; break; }; done
    [ "$mine" = 1 ] || continue
    read -r st 2>/dev/null <"$p/stat" || continue
    st=${st##*) }; read -r -a e <<<"$st"   # e[0] state, e[1] parent
    [ "${e[0]}" = Z ] && continue
    # the bus daemon (child of dbus-run-session), Xwayland and KWin's input method (children of KWin)
    [[ " $PFV_KEEP " == *" ${e[1]} "* && "${e[1]}" != "$$" ]] && continue
    PFV_PIDS+=("$pid")
  done
}
pfv_teardown() {
  trap '' TERM
  local p st pid round t left names c
  # this shell and its ancestors: KWin, dbus-run-session, timeout, vsession.sh, ...
  PFV_KEEP=$$; p=$PPID
  while [ "${p:-1}" -gt 1 ]; do
    PFV_KEEP+=" $p"
    read -r st 2>/dev/null <"/proc/$p/stat" || break
    st=${st##*) }; read -r -a st <<<"$st"; p=${st[1]}
  done
  for round in 1 2 3 4; do
    pfv_pids
    [ ${#PFV_PIDS[@]} -gt 0 ] || break
    names=
    for pid in "${PFV_PIDS[@]}"; do c=; read -r c 2>/dev/null <"/proc/$pid/comm"; names+=" $pid:$c"; done
    echo "$EPOCHREALTIME round $round SIGTERM$names" >>"$OUT/teardown.log"
    kill -TERM "${PFV_PIDS[@]}" 2>/dev/null
    for ((t = 0; t < (round == 1 ? 25 : 10); t++)); do
      left=()
      for pid in "${PFV_PIDS[@]}"; do pfv_alive "$pid" && left+=("$pid"); done
      [ ${#left[@]} -gt 0 ] || break
      sleep 0.2
    done
    left=()
    for pid in "${PFV_PIDS[@]}"; do pfv_alive "$pid" && left+=("$pid"); done
    if [ ${#left[@]} -gt 0 ]; then
      echo "$EPOCHREALTIME round $round SIGKILL ${left[*]}" >>"$OUT/teardown.log"
      kill -KILL "${left[@]}" 2>/dev/null
    fi
    sleep 0.5  # services that the stopping processes asked the bus for appear now
  done
  pfv_pids
  echo "$EPOCHREALTIME done; left: ${PFV_PIDS[*]:-none}" >>"$OUT/teardown.log"
}
cleanup() { pfv_teardown; }
trap pfv_teardown EXIT
# The private bus was started before KWin, so services it activates would not know the Wayland
# socket and abort. Give the bus the session environment, as startplasma does (bus only; never
# --systemd, which would change the logged-in user's systemd manager).
dbus-update-activation-environment WAYLAND_DISPLAY QT_QPA_PLATFORM XDG_SESSION_TYPE XDG_CURRENT_DESKTOP \
  KDE_FULL_SESSION KDE_SESSION_VERSION XDG_CONFIG_DIRS QT_FORCE_STDERR_LOGGING XDG_RUNTIME_DIR HOME PATH LANG
# PFV_LANGUAGE / PFV_SHELL: bus-activated services get them too (names in bus-env, only when set)
[ -s "$PFV/bus-env" ] && dbus-update-activation-environment $(cat "$PFV/bus-env")
# PFV_XWAYLAND: KWin started Xwayland and set DISPLAY for this shell; bus-activated X11 clients need it
[ -n "${DISPLAY:-}" ] && dbus-update-activation-environment DISPLAY ${XAUTHORITY:+XAUTHORITY}
fc-cache -f >/dev/null 2>&1
# Display scale, set the way System Settings does it (KWin's own --scale only enlarges the framebuffer).
if [ "${PFV_SCALE:-1}" != 1 ]; then
  for o in $(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '/^Output:/{print $3}'); do
    kscreen-doctor "output.$o.scale.$PFV_SCALE" >/dev/null 2>&1
  done
  sleep 1
fi
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

# Extra environment for KWin and everything in the session (for example QT_PLUGIN_PATH to test a
# locally built decoration): KEY=VALUE lines in home/.config/pfv-env.
EXTRA_ENV=()
if [ -f "$PFV/home/.config/pfv-env" ]; then
  while IFS= read -r line; do
    case "$line" in ''|'#'*) ;; *=*) EXTRA_ENV+=("$line") ;; esac
  done <"$PFV/home/.config/pfv-env"
fi
if [ -n "${PFV_CWD:-}" ]; then
  mkdir -p "$PFV/$PFV_CWD" && cd "$PFV/$PFV_CWD" || exit 1
fi
OPT_ENV=()
rm -f "$PFV/bus-env"
[ -n "${PFV_LANGUAGE:-}" ] && OPT_ENV+=("LANGUAGE=$PFV_LANGUAGE") && echo LANGUAGE >>"$PFV/bus-env"
[ -n "${PFV_SHELL:-}" ] && OPT_ENV+=("SHELL=$PFV_SHELL") && echo SHELL >>"$PFV/bus-env"
[ "${PFV_LOCK:-0}" = 1 ] && OPT_ENV+=("PFV_LOCK=1")
KWIN_OPTS=(--no-lockscreen)
[ "${PFV_LOCK:-0}" = 1 ] && KWIN_OPTS=()
[ "${PFV_XWAYLAND:-0}" = 1 ] && KWIN_OPTS+=(--xwayland)
# Soft time limit: at TIMEOUT the scenario shell gets SIGTERM, which runs the teardown while KWin
# still runs; `timeout` 30 s later is the hard stop.
rm -f "$PFV/timed-out"
(
  trap 'kill "$s" 2>/dev/null; exit 0' TERM
  sleep "$TMO" & s=$!; wait "$s"
  for p in /proc/[0-9]*; do
    [ "$(cat "$p/comm" 2>/dev/null)" = inner.sh ] || continue
    grep -qz "^XDG_RUNTIME_DIR=$PFV/run\$" "$p/environ" 2>/dev/null || continue
    touch "$PFV/timed-out"; kill -TERM "${p#/proc/}"
  done
) &
WATCHDOG=$!
env -i "${EXTRA_ENV[@]}" "${OPT_ENV[@]}" HOME="$PFV/home" XDG_RUNTIME_DIR="$PFV/run" PFV="$PFV" NO_PLASMASHELL="${NO_PLASMASHELL:-0}" \
  PFV_SCALE="${PFV_SCALE:-1}" \
  PATH=/usr/bin:/bin:/usr/lib64/qt6/bin LANG=en_US.UTF-8 \
  XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=KDE KDE_FULL_SESSION=true KDE_SESSION_VERSION=6 \
  XDG_CONFIG_DIRS="$CONFIG_DIRS" QT_FORCE_STDERR_LOGGING=1 \
  QT_QPA_PLATFORM=wayland \
  timeout "$((TMO + 30))" dbus-run-session -- kwin_wayland --virtual --width "$W" --height "$H" \
    --output-count "${PFV_OUTPUTS:-1}" \
    --socket "pfv-$NAME" "${KWIN_OPTS[@]}" --exit-with-session "$PFV/inner.sh" >"$PFV/out/kwin.log" 2>&1
rc=$?
kill "$WATCHDOG" 2>/dev/null; wait "$WATCHDOG" 2>/dev/null
if [ -e "$PFV/timed-out" ]; then
  echo "session rc=124" >>"$PFV/out/scenario.log"
  echo "time limit of ${TMO} s reached: the scenario was stopped (kwin rc=$rc)" >>"$PFV/out/scenario.log"
  rm -f "$PFV/timed-out"
else
  echo "session rc=$rc" >>"$PFV/out/scenario.log"
fi

# Kill anything that still belongs to this session (matched by its private runtime dir).
for p in /proc/[0-9]*; do
  grep -qz "^XDG_RUNTIME_DIR=$PFV/run\$" "$p/environ" 2>/dev/null && kill -9 "${p#/proc/}" 2>/dev/null
done
grep -E -i "compositing type|OpenGL renderer|OpenGL version|blur" "$PFV/out/kwin-support.txt" 2>/dev/null | head -5 >"$PFV/out/compositor.txt"
ls "$PFV/out"
