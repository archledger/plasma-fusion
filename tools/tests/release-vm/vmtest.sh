#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# vmtest.sh NAME LANE: the release test in one VM (a fresh overlay of its provisioned base):
# the installer (dry run, install, status) in the user's Plasma session, a new login with Plasma
# Fusion (screenshots: desktop, launcher, lock screen), crashes and logs, then uninstall and a new
# login with the previous desktop. LANE: copr, aur, ppa, deb. Results: ~/pf-vm/results/NAME/.
# PF_PUBLIC=1: after a release, the published installer and the public channels (Copr, the AUR,
# the PPA, the release on GitHub) instead of the test channels of channels.sh.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
H=${PF_VM_HOME:-$HOME/pf-vm} C=${PF_REL:-$HOME/pf-rel}/channels
name=$1 lane=$2
OUT=$H/results/$name
rm -rf "$OUT" && mkdir -p "$OUT"
vm() { bash "$HERE/vm.sh" "$@"; }
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$OUT/steps.log"; }
# insession CMD: run CMD as pf with the environment of pf's plasmashell (the tty1 session).
insession() {
  vm ssh "$name" "pid=\$(pgrep -u pf -x 'plasmashell|\.plasmashell-wr' | head -n 1); [ -n \"\$pid\" ] || { echo 'no plasmashell'; exit 97; }
    while IFS= read -r -d '' kv; do case \${kv%%=*} in
      DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR|WAYLAND_DISPLAY|DISPLAY|XDG_CURRENT_DESKTOP|XDG_SESSION_TYPE|XDG_SESSION_DESKTOP|KDE_SESSION_VERSION|KDE_FULL_SESSION|XDG_DATA_DIRS|XDG_CONFIG_DIRS|QT_QPA_PLATFORM|XAUTHORITY|PATH|LANG) export \"\$kv\" ;;
    esac; done < /proc/\$pid/environ
    $1"
}
wait_plasma() { # wait for a settled desktop
  for _ in $(seq 1 60); do
    vm ssh "$name" 'pgrep -u pf -x "plasmashell|\.plasmashell-wr" >/dev/null' && break
    sleep 5
  done
  sleep 25
  # Plasma's welcome app opens on a first login; it would cover the desktop in the screenshots.
  vm ssh "$name" 'for p in $(pgrep -u pf -x "plasma-welcome|\.plasma-welcome"); do kill "$p"; done' 2>/dev/null || true
  sleep 3
}
# The VM's session on tty1 (loginctl list-sessions has no TTY column in every systemd version).
TTY1='tty1_session() { for s in $(loginctl list-sessions --no-legend | awk "{print \$1}"); do [ "$(loginctl show-session "$s" -p TTY --value)" = tty1 ] && [ "$(loginctl show-session "$s" -p State --value)" != closing ] && echo "$s"; done; }; '
# Log out the way the logout dialog does (Plasma stops its user units; terminating the logind session
# would leave them running under the user manager the ssh logins keep alive), then getty logs pf in
# on tty1 again and a new Plasma session starts.
relogin() {
  local before now=''
  before=$(vm ssh "$name" "$TTY1 tty1_session")
  insession "busctl --user call org.kde.Shutdown /Shutdown org.kde.Shutdown logout" >/dev/null 2>&1 || true
  for _ in $(seq 1 40); do
    sleep 3
    now=$(vm ssh "$name" "$TTY1 tty1_session" 2>/dev/null)
    [ -n "$now" ] && [ "$now" != "$before" ] && break
  done
  log "relogin: session $before -> ${now:-none}"
  wait_plasma
}
shot() { vm shot "$name" "$OUT/$1.png" >/dev/null && log "screenshot $1"; }

log "start $name ($lane)"
vm start "$name" run >/dev/null && vm wait "$name" >/dev/null || { log "FAIL: the VM did not come up"; exit 1; }
# Crash reports everywhere (Debian and Ubuntu do not install systemd-coredump by default).
case $lane in
  ppa | deb)
    vm ssh "$name" 'command -v coredumpctl >/dev/null || {
      sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get update -q &&
      sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get install -y -q systemd-coredump;
    }' || { log "FAIL: could not prepare crash collector"; exit 1; }
    ;;
esac
# No dimming, screen off or suspend in the test sessions (from the next login on).
vm ssh "$name" 'mkdir -p ~/.config && printf "[AC][Display]\nDimDisplayWhenIdle=false\nTurnOffDisplayWhenIdle=false\n\n[AC][SuspendAndShutdown]\nAutoSuspendAction=0\n" >~/.config/powerdevilrc'

wait_plasma
shot 01-stock
vm ssh "$name" 'cat /etc/os-release | grep -E "^(PRETTY_NAME|ID)="; (rpm -q kwin 2>/dev/null || pacman -Q kwin 2>/dev/null || dpkg-query -W kwin-wayland 2>/dev/null)' >"$OUT/system.txt" 2>&1
log "system: $(tr '\n' ' ' <"$OUT/system.txt")"

if [ "${PF_PUBLIC:-}" = 1 ]; then
  # The published installer, as a user runs it; on Arch an AUR helper, as an Arch user has one.
  vm ssh "$name" "curl -fsSL -o ~/install.sh https://github.com/archledger/plasma-fusion/releases/latest/download/install.sh"
  log "installer: $(vm ssh "$name" 'grep -m 1 "^PF_VERSION=" ~/install.sh')"
  env=""
  [ "$lane" = aur ] && vm ssh "$name" 'command -v yay >/dev/null || { sudo pacman -S --needed --noconfirm base-devel git >/dev/null && rm -rf ~/yay-bin && git clone -q https://aur.archlinux.org/yay-bin.git ~/yay-bin && cd ~/yay-bin && makepkg -si --noconfirm >/dev/null 2>&1; }; command -v yay'
  lane_env=public
else
  lane_env=$lane
fi
# The installer and the test channel for this lane.
if [ "$lane_env" != public ]; then
  vm ssh "$name" "curl -fsS -o ~/install.sh http://10.0.2.2:8088/install.sh && curl -fsS -o ~/test-key.asc http://10.0.2.2:8088/test-key.asc"
  PF_VER=$(tr -d '[:space:]' <"$HERE/../../../VERSION")
  env="PLASMA_FUSION_DEV=1 PLASMA_FUSION_DEV_VERSION=$PF_VER"
  # PF_DEV_ENV: more test-mode settings, for example PLASMA_FUSION_DEV_SERIES='6.7 6.8' for a
  # candidate tested with a new Plasma series.
  env="$env ${PF_DEV_ENV:-}"
fi
case $lane_env in
  copr) env="$env PLASMA_FUSION_DEV_DNF_REPO=http://10.0.2.2:8088/fedora/" ;;
  ppa) env="$env PLASMA_FUSION_DEV_APT_REPO='deb [trusted=yes] http://10.0.2.2:8088/ubuntu ./'" ;;
  # Snapshot packages are named X.Y.Z~N.gitHASH-1~target1: the installer's version is that upstream
  # version here (a release's files are X.Y.Z-1~target1).
  deb) snap=$(sed -n 's/^[0-9a-f]* *plasma-fusion_\(.*\)-1_all\.deb$/\1/p' "$C/release/SHA256SUMS" | head -n 1)
       env="${env/PLASMA_FUSION_DEV_VERSION=$PF_VER/PLASMA_FUSION_DEV_VERSION=$snap}"
       env="$env PLASMA_FUSION_DEV_RELEASE_BASE=http://10.0.2.2:8088/release PLASMA_FUSION_DEV_KEY=\$HOME/test-key.asc PLASMA_FUSION_DEV_KEY_FP=$(cat "$C/test-key.fp")" ;;
  aur)
    vm ssh "$name" 'mkdir -p ~/aur && cd ~/aur && curl -fsS -O http://10.0.2.2:8088/arch/PKGBUILD && t=$(curl -fsS http://10.0.2.2:8088/arch/ | grep -o "plasma-fusion-[0-9.]*\.tar\.gz" | head -n 1) && curl -fsS -O "http://10.0.2.2:8088/arch/$t" && sed -i -e "s|^source=.*|source=(\"$t\")|" -e "/^validpgpkeys=/d" PKGBUILD && sudo pacman -S --needed --noconfirm base-devel git >/dev/null'
    env="$env PLASMA_FUSION_DEV_AUR_SRC=\$HOME/aur" ;;
esac
log "installer: dry run"
insession "env $env sh ~/install.sh --dry-run" >"$OUT/10-dry-run.log" 2>&1
log "  rc=$? $(grep -c . "$OUT/10-dry-run.log") lines"
log "installer: install"
if [ "$lane" = nix ]; then
  # NixOS: the installer prints the configuration lines (the image has the module already); the
  # per-user step is the packaged command.
  insession "env $env sh ~/install.sh --yes; plasma-fusion setup" >"$OUT/11-install.log" 2>&1
else
  insession "env $env sh ~/install.sh --yes" >"$OUT/11-install.log" 2>&1
fi
rc=$?
log "  rc=$rc"
[ "$rc" = 0 ] || { log "FAIL: install"; tail -30 "$OUT/11-install.log"; }
insession "plasma-fusion status" >"$OUT/12-status.log" 2>&1
log "status: $(head -n 1 "$OUT/12-status.log")"
shot 13-after-setup

relogin
shot 20-fusion-desktop
insession "busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell activateLauncherMenu" >/dev/null 2>&1
sleep 4
shot 21-launcher
insession "busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell activateLauncherMenu" >/dev/null 2>&1
sleep 2
vm ssh "$name" "$TTY1"' sudo loginctl lock-session $(tty1_session)'
sleep 8
shot 22-lock
vm ssh "$name" "$TTY1"' sudo loginctl unlock-session $(tty1_session)'
sleep 4
insession "plasma-fusion status" >"$OUT/23-status-after-login.log" 2>&1
vm ssh "$name" 'tail -n 5 ~/.local/state/plasma-fusion/gate.log; echo; coredumpctl list --no-pager --since="@$(awk "/^btime/ {print \$2}" /proc/stat)" 2>&1 | tail -n 5; echo; journalctl --user -b --no-pager -p err 2>/dev/null | grep -iE "plasma-?fusion|plasmafusion" | tail -n 20' >"$OUT/24-logs.log" 2>&1
# Crashes of this boot only (the provisioned base keeps the journal of its own boots).
# A missing/failed collector is not zero crashes: abort the gate instead of hiding its status
# behind wc (Ubuntu's failed collector installation previously produced a false zero).
crashes=$(vm ssh "$name" 'python3 -' <"$HERE/crash-count.py") \
  || { log "FAIL: crash collector unavailable or failed"; exit 1; }
log "crashes: $crashes"
[ "$crashes" = 0 ] || { log "FAIL: crashes found"; exit 1; }

# PF_AFTER_LOGIN: a check of the change under test, run in the session; output in 25-after-login.log.
if [ -n "${PF_AFTER_LOGIN:-}" ]; then
  insession "$PF_AFTER_LOGIN" >"$OUT/25-after-login.log" 2>&1
  log "after-login check rc=$?: $(tail -n 1 "$OUT/25-after-login.log")"
fi

log "installer: uninstall"
if [ "$lane" = nix ]; then
  insession "plasma-fusion restore" >"$OUT/30-uninstall.log" 2>&1
else
  insession "env $env sh ~/install.sh uninstall --yes" >"$OUT/30-uninstall.log" 2>&1
fi
log "  rc=$?"
relogin
shot 31-restored
vm ssh "$name" '(rpm -qa 2>/dev/null; pacman -Qq 2>/dev/null; dpkg-query -W -f "\${db:Status-Abbrev} \${Package}\n" 2>/dev/null | awk "\$1 == \"ii\" {print \$2}") | grep "^plasma-fusion" || echo "no plasma-fusion package"; grep -h LookAndFeelPackage ~/.config/kdeglobals' >"$OUT/32-after-uninstall.txt" 2>&1
log "after uninstall: $(tr '\n' ' ' <"$OUT/32-after-uninstall.txt")"
vm stop "$name" >/dev/null
rm -f "$H/vms/$name/run.qcow2"
log "done $name"
