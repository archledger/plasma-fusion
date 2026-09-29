# shellcheck shell=bash
# Test tooling (not installed), sourced by the scenarios inside a tools/vsession session.
#
# A virtual session is not started by startplasma, so ~/.config/kdedefaults (where a Global
# Theme writes its values) is not in XDG_CONFIG_DIRS. The scenarios export it for everything
# they start and restart plasmashell with it (as a login would); KWin was started without it,
# so its keys are copied into the user files with merge-kdedefaults.py.
T=$HOME/pf-tools
export XDG_CONFIG_DIRS=$HOME/.config/kdedefaults:/etc/xdg QT_FORCE_STDERR_LOGGING=1
log() { echo "[$(date +%T)] $*"; }
login_shell() { # $1 log name: restart plasmashell as a login starts it
  kquitapp6 plasmashell >/dev/null 2>&1
  for _ in $(seq 1 20); do qdbus-qt6 | grep -qx " *org.kde.plasmashell" || break; sleep 0.5; done
  plasmashell >"$OUT/$1" 2>&1 &
  wait_for_name org.kde.plasmashell
  sleep 9
}
kwin_defaults() {
  python3 "$T/merge-kdedefaults.py" kwinrc kcminputrc kdeglobals >>"$OUT/merge.log" 2>&1
  qdbus org.kde.KWin /KWin reconfigure
  sleep 2
}
