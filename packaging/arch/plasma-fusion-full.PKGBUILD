# Maintainer: Wisbendji Fimerlus <archledger236 at gmail dot com>
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The Plasma Fusion full profile for Arch Linux (ADR 0001): a metapackage that pins the six
# plasma-fusion packages together with the fork's kwin at one exact version. Depends on
# kwin-fusion from the AUR; the stock AUR plasma-fusion package never pulls this in.
#
# Bump _kwin_pf to match kwin-fusion's _pfnum and _pfver to match its pkgver.
pkgname=plasma-fusion-full
pkgver=0.7.0
_kwin_ver=6.8.2
_kwin_pf=3
pkgrel=1
pkgdesc="The Plasma Fusion full profile: the desktop with the pinned KWin fork"
arch=(any)
url="https://github.com/archledger/plasma-fusion"
license=('GPL-2.0-or-later')
depends=("plasma-fusion=${pkgver}"
         "plasma-fusion-decoration=${pkgver}"
         "plasma-fusion-settings=${pkgver}"
         "plasma-fusion-navigation=${pkgver}"
         "plasma-fusion-quicklook=${pkgver}"
         "plasma-fusion-copytext=${pkgver}"
         "kwin-fusion=${_kwin_ver}")
optdepends=('pacman-contrib: for the IgnorePkg pinning helper')
source=()
sha256sums=()

package() {
  # The profile's marker: the installer and plasma-fusion status read it.
  install -Dm644 /dev/stdin "$pkgdir/usr/share/doc/plasma-fusion-full/PROFILE" <<EOF
profile=full
kwin=${_kwin_ver}-pf${_kwin_pf}
plasma-fusion=${pkgver}
EOF

  # The pin: the fork's kwin must not be silently replaced by a stock update.
  # Arch's pacman: add kwin-fusion to IgnorePkg in /etc/pacman.conf (the post_install says so).
  install -Dm644 /dev/stdin "$pkgdir/usr/share/doc/plasma-fusion-full/ARCH-PINNING" <<EOF
Add to /etc/pacman.conf [options]:
  IgnorePkg = kwin-fusion
This prevents a stock kwin update from silently replacing the fork while
the full profile is installed. Remove the line before --full-restore.
EOF
}

post_install() {
  echo "==> plasma-fusion-full: the KWin fork is pinned at ${_kwin_ver}-pf${_kwin_pf}"
  echo "==> Add 'IgnorePkg = kwin-fusion' to /etc/pacman.conf to hold the pin"
  echo "==> See /usr/share/doc/plasma-fusion-full/ARCH-PINNING for details"
}

post_remove() {
  echo "==> plasma-fusion-full removed: remove IgnorePkg from /etc/pacman.conf"
  echo "==> and reinstall the stock kwin package"
}
