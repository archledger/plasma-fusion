# Maintainer: Wisbendji Fimerlus <archledger236 at gmail dot com>
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The Plasma Fusion full profile for Arch Linux (ADR 0001): a metapackage that pins the six
# plasma-fusion packages together with the fork's kwin at one exact version. Depends on
# kwin-fusion from the AUR; the stock AUR plasma-fusion package never pulls this in.
#
# Bump _kwin_upstream and _kwin_pf to match kwin-fusion's _upstream and _pfnum, and pkgver to
# the Plasma Fusion release the pair ships with (the repository's VERSION).
pkgname=plasma-fusion-full
pkgver=0.7.0
_kwin_upstream=6.8.2
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
         "kwin-fusion=${_kwin_upstream}.pf${_kwin_pf}")
install=plasma-fusion-full.install
source=("plasma-fusion-full.install")
sha256sums=('SKIP')

package() {
  # The profile's marker: the installer and plasma-fusion status read it.
  install -Dm644 /dev/stdin "$pkgdir/usr/share/doc/plasma-fusion-full/PROFILE" <<EOF
profile=full
kwin=${_kwin_upstream}-pf${_kwin_pf}
plasma-fusion=${pkgver}
EOF

  # The pin: the fork's kwin must not be silently replaced by a stock update.
  # Arch's pacman: add kwin-fusion to IgnorePkg in /etc/pacman.conf (the install scriptlet says so).
  install -Dm644 /dev/stdin "$pkgdir/usr/share/doc/plasma-fusion-full/ARCH-PINNING" <<EOF
Add to /etc/pacman.conf [options]:
  IgnorePkg = kwin-fusion
This prevents a stock kwin update from silently replacing the fork while
the full profile is installed. Remove the line before --full-restore.
EOF
}
