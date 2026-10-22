#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# splashtest.sh NAME LANE: the boot splash on real boots in one VM (a fresh overlay of its base).
# The kernel command line of a desktop's boot ("quiet splash"; the VMs also log to a serial
# console, with which Plymouth shows its text splash only, so plymouth.ignore-serial-consoles; and
# plymouth.debug, for Plymouth's log); the package from the lane's channel, installed with the
# installer in the tty1 session as vmtest.sh does, which must offer the boot splash step; a reboot
# with the system's own splash, which must not look like the Splash board; plymouth-install.sh
# --select, as the installer suggests, and a reboot with the Plasma Fusion splash: screendumps
# from the VM's reset on (splash-capture.py), one of which must match the board; Plymouth's log
# must show a graphical display and the script plugin, and the desktop must start after it. Then
# the installer's uninstall, which removes the splash, its state and the packages its installer
# added, and selects the system's theme again (no Plymouth on Arch), then a reboot without the
# board's look. Each captured boot runs without the tty1 log-in, since Plasma Fusion's log-in
# splash looks like the board too: the log-in follows the capture. LANE: copr, aur, ppa, deb (as
# vmtest.sh; not nix, where the NixOS module sets boot.plymouth). Needs Pillow for the comparison
# (on NixOS: nix-shell -p python3Packages.pillow). Results: ~/pf-vm/results/NAME-splash/.
# PF_SPLASH_SECONDS: how long each boot is captured from the reset on (default 60).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
H=${PF_VM_HOME:-$HOME/pf-vm} C=${PF_REL:-$HOME/pf-rel}/channels
name=$1 lane=$2
OUT=$H/results/$name-splash
rm -rf "$OUT" && mkdir -p "$OUT"
TOOLS=/usr/share/plasma-fusion/tools/system
THEME=/usr/share/plymouth/themes/plasma-fusion
ARGS="quiet splash plymouth.ignore-serial-consoles plymouth.debug"
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
      saved=$H/vms/$name/failed-splash-run-$(date -u +%Y%m%dT%H%M%S)-$$.qcow2
      mv "$disk" "$saved" || { log "FAIL: could not preserve failed overlay"; exit 1; }
      log "failed overlay preserved: $saved"
    fi
  fi
  [ "$status" != 0 ] || log "done $name (boot splash)"
  exit "$status"
}
# insession CMD: run CMD as pf with the environment of pf's plasmashell (the tty1 session).
insession() {
  vm ssh "$name" "pid=\$(pgrep -u pf -x 'plasmashell|\.plasmashell-wr' | head -n 1); [ -n \"\$pid\" ] || { echo 'no plasmashell'; exit 97; }
    while IFS= read -r -d '' kv; do case \${kv%%=*} in
      DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR|WAYLAND_DISPLAY|DISPLAY|XDG_CURRENT_DESKTOP|XDG_SESSION_TYPE|XDG_SESSION_DESKTOP|KDE_SESSION_VERSION|KDE_FULL_SESSION|XDG_DATA_DIRS|XDG_CONFIG_DIRS|QT_QPA_PLATFORM|XAUTHORITY|PATH|LANG) export \"\$kv\" ;;
    esac; done < /proc/\$pid/environ
    $1"
}
wait_plasma() { # wait for a settled desktop; 1 when none started
  local _
  for _ in $(seq 1 60); do
    vm ssh "$name" 'pgrep -u pf -x "plasmashell|\.plasmashell-wr" >/dev/null' && break
    sleep 5
  done
  vm ssh "$name" 'pgrep -u pf -x "plasmashell|\.plasmashell-wr" >/dev/null' || return 1
  sleep 25
  vm ssh "$name" 'for p in $(pgrep -u pf -x "plasma-welcome|\.plasma-welcome"); do kill "$p"; done' 2>/dev/null || true
  sleep 3
}
crashes() { vm ssh "$name" 'python3 -' <"$HERE/crash-count.py"; }
# The theme Plymouth selects: plymouth-set-default-theme's, else the default.plymouth alternative's
# (Ubuntu, KDE neon); "none" without either (Arch before the install has no Plymouth).
selected() {
  vm ssh "$name" 'sudo sh -s' <<'EOF'
if command -v plymouth-set-default-theme >/dev/null; then plymouth-set-default-theme; exit; fi
v=$(update-alternatives --query default.plymouth 2>/dev/null | sed -n 's/^Value: //p')
echo "${v:-none}"
EOF
}
# Reboot with the screen captured from the reset on (splash-capture.py, $2 match or differ), then
# the desktop, this boot's command line and Plymouth's log. Plasma Fusion's own log-in splash
# (KSplash) looks like the board too: the boot runs without the tty1 log-in (the base's autologin
# drop-in set aside), so only Plymouth draws until the log-in prompt, and the log-in follows the
# capture (getty@tty1 restarted with the drop-in back).
AUTOLOGIN=/etc/systemd/system/getty@tty1.service.d/autologin.conf
boot() { # $1 name of the results, $2 match or differ
  local rc=0
  # (Plymouth writes its log when it runs; a boot without it would leave the last one)
  vm ssh "$name" "sudo rm -f /var/log/plymouth-debug.log && sudo mv $AUTOLOGIN $AUTOLOGIN.off" ||
    fail "could not set the tty1 log-in aside ($1)"
  python3 "$HERE/splash-capture.py" "$H/vms/$name/qmp.sock" "$OUT/$1" --expect "$2" \
    --seconds "${PF_SPLASH_SECONDS:-60}" -- \
    bash "$HERE/vm.sh" ssh "$name" 'sudo systemctl reboot' >"$OUT/$1-capture.txt" 2>&1 || rc=$?
  vm wait "$name" >/dev/null || fail "no ssh after the reboot ($1)"
  vm ssh "$name" "sudo mv $AUTOLOGIN.off $AUTOLOGIN && sudo systemctl daemon-reload && sudo systemctl restart getty@tty1" ||
    fail "could not log in on tty1 again ($1)"
  wait_plasma || fail "no desktop after the reboot ($1)"
  vm ssh "$name" 'cat /proc/cmdline' >"$OUT/$1-cmdline.txt" 2>&1
  vm ssh "$name" 'sudo cat /var/log/plymouth-debug.log 2>/dev/null' >"$OUT/$1-plymouth-debug.log" 2>&1
  [ "$rc" != 2 ] || fail "the VM did not reset ($1)"
  for a in splash plymouth.ignore-serial-consoles; do
    grep -qw -- "$a" "$OUT/$1-cmdline.txt" || fail "the boot's command line lacks $a ($1)"
  done
  log "  $(tail -n 1 "$OUT/$1-capture.txt")"
  return "$rc"
}

log "start $name ($lane, boot splash)"
case $lane in copr | aur | ppa | deb) ;; *) fail "lane $lane: copr, aur, ppa or deb" ;; esac
python3 -c 'import PIL' 2>/dev/null || fail "Pillow is missing for splash-capture.py"
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
wait_plasma || fail "no desktop on the first boot"
vm ssh "$name" 'cat /etc/os-release | grep -E "^(PRETTY_NAME|ID)="' >"$OUT/system.txt" 2>&1
log "system: $(tr '\n' ' ' <"$OUT/system.txt")"

# The splash's kernel arguments, through the system's boot loader (the bases boot with GRUB):
# Fedora's grubby (BLS entries), a GRUB drop-in where the system reads /etc/default/grub.d (Debian,
# Ubuntu and KDE neon, whose cloud settings there set GRUB_CMDLINE_LINUX_DEFAULT), else
# /etc/default/grub itself (Arch)
vm ssh "$name" "sudo ARGS='$ARGS' sh -es" >"$OUT/10-cmdline.log" 2>&1 <<'EOF' ||
if command -v grubby >/dev/null; then
  grubby --update-kernel=ALL --args="$ARGS"
elif [ -d /etc/default/grub.d ] && command -v update-grub >/dev/null; then
  printf 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT %s"\n' "$ARGS" >/etc/default/grub.d/99-pf-splash-test.cfg
  update-grub
else
  sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"/&$ARGS /" /etc/default/grub
  grub-mkconfig -o /boot/grub/grub.cfg
fi
EOF
  { tail -20 "$OUT/10-cmdline.log"; fail "could not add the splash's kernel arguments"; }
log "kernel arguments added: $ARGS"

# The package, as vmtest.sh installs it
# shellcheck source=tools/tests/release-vm/lane-env.sh
. "$HERE/lane-env.sh"
lane_installer || fail "could not prepare AUR build prerequisites"
log "installer: install"
insession "env $env sh ~/install.sh --yes" >"$OUT/11-install.log" 2>&1 || { tail -30 "$OUT/11-install.log"; fail "install"; }
grep -q "plymouth-install.sh --select" "$OUT/11-install.log" && log "  the installer offers the boot splash step" ||
  fail "the installer did not offer the boot splash step"
stock=$(selected)
log "stock splash theme: ${stock:-not named}"
[ -n "$stock" ] && [ "$stock" != plasma-fusion ] || fail "the stock splash theme is ${stock:-not named}"

boot 20-stock differ || fail "the stock boot looks like the Splash board"

# Arch: Plymouth into pacman's cache first, tried three times (the mirrors time out now and then
# from QEMU's user network, and pacman has no retries of its own): the installer's own pacman -S
# then installs it from there
if [ "$lane" = aur ]; then
  vm ssh "$name" 'for try in 1 2 3; do sudo pacman -Sw --needed --noconfirm plymouth >/dev/null && exit 0; sleep 15; done; exit 1' ||
    fail "could not download Plymouth"
fi
# plymouth-install.sh as the installer suggests it
rc=0; vm ssh "$name" "sudo $TOOLS/plymouth-install.sh --select" >"$OUT/30-select.log" 2>&1 || rc=$?
log "plymouth-install.sh --select: rc=$rc"
[ "$rc" = 0 ] || { tail -20 "$OUT/30-select.log"; fail "plymouth-install.sh --select"; }
vm ssh "$name" 'sudo sh -ec "if [ -e /var/lib/plasma-fusion/plymouth/installed-packages ]; then cat /var/lib/plasma-fusion/plymouth/installed-packages; fi"' \
  >"$OUT/30-installed-packages.txt" || fail "could not read the splash installer's packages"
log "installed by the splash installer: $(xargs <"$OUT/30-installed-packages.txt")"
theme=$(selected)
log "  selected: $theme"
case $theme in plasma-fusion | "$THEME/plasma-fusion.plymouth") ;; *) fail "plymouth-install.sh selected ${theme:-nothing}" ;; esac

boot 32-fusion match || fail "no frame of the boot looks like the Splash board"
# Plymouth's log of this boot: a pixel display (not the text splash), the script plugin running
grep -E -m 1 "adding [0-9]+x[0-9]+ pixel display" "$OUT/32-fusion-plymouth-debug.log" >"$OUT/32-plymouth.txt" ||
  fail "Plymouth's log names no pixel display (32-fusion-plymouth-debug.log)"
grep -E -m 1 "theme file is" "$OUT/32-fusion-plymouth-debug.log" >>"$OUT/32-plymouth.txt" || true
grep -q "executing script file" "$OUT/32-fusion-plymouth-debug.log" ||
  fail "Plymouth's log does not show the script plugin running (32-fusion-plymouth-debug.log)"
# (Plymouth's trace lines: "HH:MM:SS.mmm FILE:LINE:FUNCTION", padded, then ": " and the message)
while IFS= read -r line; do log "  plymouth: ${line#*: }"; done <"$OUT/32-plymouth.txt"
n=$(crashes) || fail "crash collector unavailable or failed"
log "crashes: $n"
[ "$n" = 0 ] || fail "crashes found"

# The installer's uninstall removes the splash before the packages go
insession "env $env sh ~/install.sh uninstall --yes" >"$OUT/40-uninstall.log" 2>&1 || { tail -30 "$OUT/40-uninstall.log"; fail "uninstall"; }
# No other package needs the installer's packages on these fresh VMs: none may remain, nor any
# state. Read failures must not look like an empty directory or an absent package.
vm ssh "$name" "sudo sh -ec 'if test -e $THEME; then echo $THEME; fi; if [ -d /var/lib/plasma-fusion/plymouth ]; then ls -A /var/lib/plasma-fusion/plymouth; fi'" \
  >"$OUT/41-leftovers.txt" 2>&1 || fail "could not check the splash's remaining files"
[ ! -s "$OUT/41-leftovers.txt" ] || fail "the splash is still installed after uninstall (41-leftovers.txt)"
vm ssh "$name" 'bash -se' >"$OUT/41-installed-packages.txt" <<'EOF' ||
set -o pipefail
if command -v rpm >/dev/null; then rpm -qa --qf '%{NAME}\n'
elif command -v pacman >/dev/null; then pacman -Qq
else dpkg-query -W -f='${Package} ${db:Status-Status}\n' | awk '$2 == "installed" {print $1}'
fi
EOF
  fail "could not list installed packages after uninstall"
while IFS= read -r p; do
  [ -z "$p" ] || ! grep -qxF "$p" "$OUT/41-installed-packages.txt" ||
    fail "the splash installer's package is still installed: $p"
done <"$OUT/30-installed-packages.txt"
log "the splash installer's packages are removed"
theme=$(selected)
log "splash theme after uninstall: ${theme:-not named}"
[ -n "$theme" ] && [ "$theme" != plasma-fusion ] && [ "$theme" != "$THEME/plasma-fusion.plymouth" ] ||
  fail "the splash theme after uninstall is ${theme:-not named}"
[ "$theme" = "$stock" ] || fail "the splash theme after uninstall is $theme, not the stock $stock"

boot 42-restored differ || fail "the boot after uninstall still looks like the Splash board"
n=$(crashes) || fail "crash collector unavailable or failed"
log "final crashes: $n"
[ "$n" = 0 ] || fail "crashes found after the uninstall"
