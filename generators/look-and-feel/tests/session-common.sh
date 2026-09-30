# shellcheck shell=bash
# Test tooling (not installed), sourced by the scenarios inside a tools/vsession session.
#
# A Global Theme writes its values to ~/.config/kdedefaults, which startplasma puts first in
# XDG_CONFIG_DIRS. tools/vsession/vsession.sh does the same for the whole session (KWin
# included) since commit 0918220, so the export below only repeats it, and kwin_defaults()'s
# merge-kdedefaults.py is a no-op there (kwriteconfig6 skips values the cascade already has);
# both are kept for copies of the older vsession.sh, whose KWin started without kdedefaults.
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
