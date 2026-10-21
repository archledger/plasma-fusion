# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The installer for one release-VM test (vmtest.sh, sddmtest.sh), sourced. lane_installer puts the
# installer (and the lane's test key or sources) into the VM and sets env, the environment it runs
# with, and lane_env, the lane or "public" (PF_PUBLIC=1). It expects name, lane, C and HERE, and the
# functions vm and log; it returns 1 when the AUR lane's prerequisites cannot be prepared (pacman
# tries three times: it has no retries of its own, and the mirrors time out now and then from QEMU's
# user network).
# shellcheck disable=SC2154 # name and lane: set by the script that sources this file
lane_installer() {
  local snap
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
      vm ssh "$name" 'mkdir -p ~/aur && cd ~/aur && curl -fsS -O http://10.0.2.2:8088/arch/PKGBUILD && t=$(curl -fsS http://10.0.2.2:8088/arch/ | grep -o "plasma-fusion-[0-9.]*\.tar\.gz" | head -n 1) && curl -fsS -O "http://10.0.2.2:8088/arch/$t" && sed -i -e "s|^source=.*|source=(\"$t\")|" -e "/^validpgpkeys=/d" PKGBUILD && for try in 1 2 3; do sudo pacman -Syu --needed --noconfirm base-devel git && break; [ $try != 3 ] || exit 1; sleep 15; done && command -v debugedit && command -v fakeroot' \
        || return 1
      env="$env PLASMA_FUSION_DEV_AUR_SRC=\$HOME/aur" ;;
  esac
}
