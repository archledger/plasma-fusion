#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# sddmtest.sh NAME LANE: the SDDM login screen on real boots in one VM (a fresh overlay of its
# base). The package from the lane's channel, installed with the installer in the tty1 session as
# vmtest.sh does; then SDDM made the display manager (the bases log pf in on tty1 without one) and
# a reboot to the system's own greeter; greeter-apply.sh, as the installer suggests, and a reboot
# to the Plasma Fusion greeter: the theme SDDM loaded, no warning from the theme's files, the screen
# compared with the Login board (greeter-compare.py), and the test user's password typed into it,
# which must start a Plasma session; then the installer's uninstall, which restores the login
# screen, and a reboot to the system's greeter again. LANE: copr, aur, ppa, deb (as vmtest.sh; not
# nix, where the NixOS module chooses SDDM's theme). Needs Pillow for the comparison (on NixOS:
# nix-shell -p python3Packages.pillow). Results: ~/pf-vm/results/NAME-sddm/.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
H=${PF_VM_HOME:-$HOME/pf-vm} C=${PF_REL:-$HOME/pf-rel}/channels
name=$1 lane=$2
OUT=$H/results/$name-sddm
rm -rf "$OUT" && mkdir -p "$OUT"
# The test user's password, for SDDM's prompt (the bases have none: pf logs in on tty1)
PASSWORD=pf-sddm-test
TOOLS=/usr/share/plasma-fusion/tools/system
THEME=/usr/share/sddm/themes/plasmafusion
vm() { bash "$HERE/vm.sh" "$@"; }
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$OUT/steps.log"; }
fail() { log "FAIL: $*"; exit 1; }
cleanup_vm() {
  local status=$1 disk=$H/vms/$name/run.qcow2
  trap - EXIT
  vm stop "$name" >/dev/null || { log "FAIL: could not stop the VM during cleanup"; exit 1; }
  if [ -f "$disk" ]; then
    if [ "$status" = 0 ]; then
      rm -f "$disk"
    else
      local saved
      saved=$H/vms/$name/failed-sddm-run-$(date -u +%Y%m%dT%H%M%S)-$$.qcow2
      mv "$disk" "$saved" || { log "FAIL: could not preserve failed overlay"; exit 1; }
      log "failed overlay preserved: $saved"
    fi
  fi
  [ "$status" != 0 ] || log "done $name (SDDM)"
  exit "$status"
}
# insession CMD: run CMD as pf with the environment of pf's plasmashell (tty1's, later SDDM's).
insession() {
  vm ssh "$name" "pid=\$(pgrep -u pf -x 'plasmashell|\.plasmashell-wr' | head -n 1); [ -n \"\$pid\" ] || { echo 'no plasmashell'; exit 97; }
    while IFS= read -r -d '' kv; do case \${kv%%=*} in
      DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR|WAYLAND_DISPLAY|DISPLAY|XDG_CURRENT_DESKTOP|XDG_SESSION_TYPE|XDG_SESSION_DESKTOP|KDE_SESSION_VERSION|KDE_FULL_SESSION|XDG_DATA_DIRS|XDG_CONFIG_DIRS|QT_QPA_PLATFORM|XAUTHORITY|PATH|LANG) export \"\$kv\" ;;
    esac; done < /proc/\$pid/environ
    $1"
}
wait_plasma() { # wait for a settled desktop
  local _
  for _ in $(seq 1 60); do
    vm ssh "$name" 'pgrep -u pf -x "plasmashell|\.plasmashell-wr" >/dev/null' && break
    sleep 5
  done
  sleep 25
  vm ssh "$name" 'for p in $(pgrep -u pf -x "plasma-welcome|\.plasma-welcome"); do kill "$p"; done' 2>/dev/null || true
  sleep 3
}
shot() { vm shot "$name" "$OUT/$1.png" >/dev/null && log "screenshot $1"; }
monitor() { # send monitor commands (one per line on stdin) to the VM's QEMU
  python3 -c "
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); time.sleep(0.3); s.recv(65536)
for line in sys.stdin.read().splitlines():
    s.sendall((line + '\n').encode()); time.sleep(0.15)
time.sleep(0.3); s.close()" "$H/vms/$name/mon.sock"
}
type_line() { # $1 text (lower-case letters, digits, -), then Return: QEMU key events
  local i ch
  for ((i = 0; i < ${#1}; i++)); do
    ch=${1:i:1}
    case $ch in -) echo "sendkey minus" ;; *) echo "sendkey $ch" ;; esac
  done | monitor
  echo "sendkey ret" | monitor
}
# Reboot, wait for SDDM's greeter to load a theme (its own "Loading .../Main.qml" line, on X11 and on
# Wayland alike), then a screenshot and the boot's SDDM and greeter journal.
reboot_to_greeter() { # $1 name of the screenshot
  local _
  vm ssh "$name" 'sudo systemctl reboot' >/dev/null 2>&1 || true
  for _ in $(seq 1 40); do sleep 3; vm ssh "$name" true 2>/dev/null || break; done
  vm wait "$name" >/dev/null || fail "no ssh after the reboot ($1)"
  for _ in $(seq 1 60); do
    vm ssh "$name" 'sudo journalctl -b --no-pager 2>/dev/null | grep -qE "sddm-greeter[^:]*: Loading [^ ]*/Main\.qml"' && break
    sleep 3
  done
  # The greeter paints after its session starts
  sleep 15
  shot "$1"
  # (without this script's own sudo lines, which name sddm too)
  vm ssh "$name" 'sudo journalctl -b --no-pager -o short-monotonic 2>/dev/null | grep -E "sddm|greeter" | grep -v " sudo\["' >"$OUT/$1-journal.log" 2>&1
  grep -qE "sddm-greeter[^:]*: Loading [^ ]*/Main\.qml" "$OUT/$1-journal.log" || fail "SDDM's greeter did not start ($1)"
}
# The theme directory the greeter of this boot loaded, from its journal ("embedded": SDDM's own, when
# the configured theme is missing)
greeter_theme() {
  sed -n -e 's|.*sddm-greeter[^:]*: Loading file://\(.*\)/Main\.qml.*|\1|p' \
    -e 's|.*sddm-greeter[^:]*: Loading qrc:/.*/Main\.qml.*|embedded|p' "$OUT/$1-journal.log" | tail -n 1
}
compare() { # $1 screenshot, $2 match or differ
  python3 "$HERE/greeter-compare.py" "$OUT/$1.png" --expect "$2" >"$OUT/$1-compare.txt" 2>&1
}
crashes() { vm ssh "$name" 'python3 -' <"$HERE/crash-count.py"; }

log "start $name ($lane, SDDM)"
case $lane in copr | aur | ppa | deb) ;; *) fail "lane $lane: copr, aur, ppa or deb" ;; esac
python3 -c 'import PIL' 2>/dev/null || fail "Pillow is missing for greeter-compare.py"
vm start "$name" run >/dev/null || fail "the VM did not start"
trap 'cleanup_vm $?' EXIT
vm wait "$name" >/dev/null || fail "the VM did not come up"
case $lane in
  ppa | deb)
    vm ssh "$name" 'command -v coredumpctl >/dev/null || {
      sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get update -q &&
      sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get install -y -q systemd-coredump;
    }' >/dev/null || fail "could not prepare the crash collector"
    ;;
esac
wait_plasma
vm ssh "$name" 'cat /etc/os-release | grep -E "^(PRETTY_NAME|ID)="' >"$OUT/system.txt" 2>&1
log "system: $(tr '\n' ' ' <"$OUT/system.txt")"

# SDDM as the display manager, before the install (the installer offers the login screen step
# where SDDM's Qt 6 greeter is): installed where the base lacks it, with the display server its
# greeter runs on there (Fedora's KDE pairing sddm-wayland-plasma, with its theme sddm-breeze; Arch's
# and Debian's SDDM start; pacman, which has no retries of its own, tries three times: the mirrors
# time out now and then from QEMU's user network)
# an X server), enabled in place of the tty1 login (from the next boot), and the test user given a
# password to type into it. KDE's first-run wizard (plasma-setup, Fedora 44) counts as done, as on
# an installed system: until /etc/plasma-setup-done exists it logs its own user in through SDDM
# (/etc/sddm.conf.d/99-plasma-setup.conf) and no greeter shows.
vm ssh "$name" "set -e
  case $lane in
    copr) sudo dnf -y -q install sddm sddm-wayland-plasma sddm-breeze ;;
    aur) for try in 1 2 3; do sudo pacman -S --needed --noconfirm sddm xorg-server && break
           [ \$try != 3 ] || exit 1; sleep 15; done ;;
    *) [ -x /usr/bin/sddm-greeter-qt6 ] && [ -x /usr/lib/xorg/Xorg ] ||
         sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get install -y -q sddm xserver-xorg-core ;;
  esac
  sudo rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf /etc/sddm.conf.d/99-plasma-setup.conf
  sudo touch /etc/plasma-setup-done
  sudo systemctl enable --force sddm.service
  sudo systemctl set-default graphical.target
  echo 'pf:$PASSWORD' | sudo chpasswd
  echo \"display manager: \$(readlink /etc/systemd/system/display-manager.service)\"
  (rpm -q sddm 2>/dev/null || pacman -Q sddm 2>/dev/null || dpkg-query -W sddm 2>/dev/null)" >"$OUT/10-sddm.log" 2>&1 ||
  fail "could not make SDDM the display manager"
log "$(grep '^display manager:' "$OUT/10-sddm.log"), $(tail -n 1 "$OUT/10-sddm.log")"
# The package, as vmtest.sh installs it
# shellcheck source=tools/tests/release-vm/lane-env.sh
. "$HERE/lane-env.sh"
lane_installer || fail "could not prepare AUR build prerequisites"
log "installer: install"
insession "env $env sh ~/install.sh --yes" >"$OUT/11-install.log" 2>&1 || { tail -30 "$OUT/11-install.log"; fail "install"; }
grep -q "greeter-apply.sh" "$OUT/11-install.log" && log "  the installer offers the login screen step" ||
  fail "the installer did not offer the login screen step (SDDM's Qt 6 greeter installed?)"

rc=0; vm ssh "$name" "bash $TOOLS/greeter-apply.sh --check" >"$OUT/12-check-before.log" 2>&1 || rc=$?
log "check before (as pf): rc=$rc"
[ "$rc" = 1 ] || fail "greeter-apply.sh --check before: rc=$rc, 1 wanted (another theme)"

reboot_to_greeter 20-stock-greeter
stock=$(greeter_theme 20-stock-greeter)
log "stock greeter theme: ${stock:-not named}"
compare 20-stock-greeter differ || fail "the stock greeter looks like the Login board ($(tail -n 1 "$OUT/20-stock-greeter-compare.txt"))"
log "  $(tail -n 1 "$OUT/20-stock-greeter-compare.txt")"

# greeter-apply.sh as the installer suggests it
rc=0; vm ssh "$name" "sudo $TOOLS/greeter-apply.sh" >"$OUT/30-apply.log" 2>&1 || rc=$?
log "greeter-apply.sh: rc=$rc"
[ "$rc" = 0 ] || { tail -20 "$OUT/30-apply.log"; fail "greeter-apply.sh"; }
rc=0; vm ssh "$name" "bash $TOOLS/greeter-apply.sh --check" >"$OUT/31-check.log" 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "greeter-apply.sh --check after: rc=$rc"

reboot_to_greeter 32-fusion-greeter
theme=$(greeter_theme 32-fusion-greeter)
log "greeter theme: ${theme:-not named}"
[ "$theme" = "$THEME" ] || fail "SDDM started its greeter with ${theme:-no theme}, not $THEME"
# Warnings that name the theme's files (Qt's own components warn without them)
grep -F "file://$THEME/" "$OUT/32-fusion-greeter-journal.log" | grep -v "Loading file://" >"$OUT/32-theme-warnings.log" || true
log "  warnings from the theme's files: $(grep -c . "$OUT/32-theme-warnings.log")"
[ ! -s "$OUT/32-theme-warnings.log" ] || fail "the greeter warned about the theme (32-theme-warnings.log)"
compare 32-fusion-greeter match || fail "the greeter does not look like the Login board ($(tail -n 1 "$OUT/32-fusion-greeter-compare.txt"))"
log "  $(tail -n 1 "$OUT/32-fusion-greeter-compare.txt")"

# The password typed into the theme's field (it has the focus): a Plasma session from SDDM
type_line "$PASSWORD"
for _ in $(seq 1 40); do
  vm ssh "$name" 'pgrep -u pf -x "plasmashell|\.plasmashell-wr" >/dev/null' && break
  sleep 3
done
vm ssh "$name" 'for s in $(loginctl list-sessions --no-legend | awk "{print \$1}"); do [ "$(loginctl show-session "$s" -p Name --value)" = pf ] && loginctl show-session "$s" -p Service -p Type -p State; done' >"$OUT/33-session.txt" 2>&1
log "session: $(tr '\n' ' ' <"$OUT/33-session.txt")"
grep -qx "Service=sddm" "$OUT/33-session.txt" || fail "no session for pf from SDDM after the password"
wait_plasma
shot 34-session
insession "plasma-fusion status" >"$OUT/35-status.log" 2>&1 || fail "plasma-fusion status in SDDM's session"
log "status: $(grep -m 1 "login screen" "$OUT/35-status.log")"
grep -q "login screen (SDDM): Plasma Fusion" "$OUT/35-status.log" || fail "status does not name the Plasma Fusion login screen"
n=$(crashes) || fail "crash collector unavailable or failed"
log "crashes: $n"
[ "$n" = 0 ] || fail "crashes found"

# The installer's uninstall restores the login screen before the packages go
insession "env $env sh ~/install.sh uninstall --yes" >"$OUT/40-uninstall.log" 2>&1 || { tail -30 "$OUT/40-uninstall.log"; fail "uninstall"; }
log "uninstall: $(grep -c "greeter-restore\|Undo the run" "$OUT/40-uninstall.log") restore lines"
vm ssh "$name" 'for f in /etc/sddm.conf.d/kde_settings.conf /etc/sddm.conf; do [ -f "$f" ] && { echo "== $f"; cat "$f"; }; done; ls /var/lib/plasma-fusion 2>&1' >"$OUT/41-sddm-files.txt" 2>&1
grep -q "plasmafusion" "$OUT/41-sddm-files.txt" && fail "SDDM's files still name the theme after uninstall (41-sddm-files.txt)"

reboot_to_greeter 42-restored-greeter
theme=$(greeter_theme 42-restored-greeter)
log "greeter theme after uninstall: ${theme:-not named}"
[ "$theme" = "$stock" ] || fail "the greeter theme after uninstall is ${theme:-not named}, not the stock ${stock:-not named}"
compare 42-restored-greeter differ || fail "the restored greeter still looks like the Login board"
n=$(crashes) || fail "crash collector unavailable or failed"
log "final crashes: $n"
[ "$n" = 0 ] || fail "crashes found after the restore"
