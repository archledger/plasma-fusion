# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Provisioning, all systems (appended to the per-system part; run as root).
# Shared tail of every provisioning script (run as root): log user pf in on tty1 and start a Plasma
# Wayland session there, without a display manager; terminating pf's session logs in again.
set -euo pipefail
for dm in sddm plasmalogin plasma-login-manager gdm lightdm; do systemctl disable "$dm" >/dev/null 2>&1 || true; done
systemctl set-default multi-user.target >/dev/null
agetty=$(command -v agetty)
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat >/etc/systemd/system/getty@tty1.service.d/autologin.conf <<UNIT
[Service]
ExecStart=
ExecStart=-$agetty --autologin pf --noclear %I \$TERM
UNIT
cat >/home/pf/.bash_profile <<'PROFILE'
[ -f ~/.bashrc ] && . ~/.bashrc
if [ "$(tty)" = /dev/tty1 ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  exec startplasma-wayland >"$HOME/.plasma-tty1.log" 2>&1
fi
PROFILE
chown pf: /home/pf/.bash_profile
# No screen locking or blanking during the tests.
mkdir -p /home/pf/.config
printf '[Daemon]\nAutolock=false\nLockOnResume=false\nTimeout=0\n' >/home/pf/.config/kscreenlockerrc
chown -R pf: /home/pf/.config
systemctl daemon-reload
echo "provisioned: $(. /etc/os-release && echo "$PRETTY_NAME")"
