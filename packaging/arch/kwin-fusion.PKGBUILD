# Maintainer: Wisbendji Fimerlus <archledger236 at gmail dot com>
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The Plasma Fusion fork of KWin for Arch Linux (the full profile's pinned compositor, ADR 0001
# in archledger/plasma-fusion). Built from the fork's signed release tag. The full profile
# installs this alongside the plasma-fusion packages; the stock profile never touches it.
#
# The _pfnum is the fork's sequence number (v<version>-pf<N> tags); bump it with each fork
# release. The exact version pins in plasma-fusion-full must match.
pkgname=kwin-fusion
pkgver=6.8.2
_pfnum=3
pkgrel=1
pkgdesc="KDE Window Manager — the Plasma Fusion fork (the full profile's pinned compositor)"
arch=(x86_64)
url="https://github.com/archledger/kwin"
license=('BSD-2-Clause' 'BSD-3-Clause' 'CC0-1.0' 'GPL-2.0-only' 'GPL-2.0-or-later' 'GPL-3.0-only' 'GPL-3.0-or-later' 'LGPL-2.0-only' 'LGPL-2.0-or-later' 'LGPL-2.1-only' 'LGPL-2.1-or-later' 'LGPL-3.0-only' 'MIT')
depends=(kwin-common kwin-libs)
makedepends=(git cmake ninja extra-cmake-modules qt6-base qt6-base-private-devel qt6-declarative
             qt6-tools qt6-wayland qt6-svg qt6-5compat
             kf6-kcompletion kf6-kconfig kf6-kconfigwidgets kf6-kcoreaddons kf6-kcrash
             kf6-kdeclarative kf6-kglobalaccel kf6-ki18n kf6-kidletime kf6-kio
             kf6-knewstuff kf6-knotifications kf6-kpackage kf6-kservice kf6-ktextwidgets
             kf6-kwidgetsaddons kf6-kwindowsystem kf6-kxmlgui kf6-solid kf6-sonnet
             plasma-activities libplasma kdecoration plasma-workspace libkscreen
             libxcvt libxkbcommon libxkbcommon-x11 libXi libX11 libxcb libxcb-cursor
             libxcb-keysyms libxcb-util libepoxy mesa libcap lcms2 glib2
             pipewire wayland-protocols libinput libevdev libudev
             systemsettings qt6-virtualkeyboard breeze
             cmake  # for the macros.kwin file
             )
provides=("kwin=${pkgver}")
conflicts=('kwin')
source=("kwin-fusion::git+https://github.com/archledger/kwin.git#tag=v${pkgver}-pf${_pfnum}?signed")
sha256sums=('SKIP')
validpgpkeys=('F35053398E3C80FE20891B82C10B8492BD7F30C6') # Wisbendji Fimerlus (release key)

build() {
  cd kwin-fusion
  cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBEXECDIR=lib \
    -DBUILD_TESTING=OFF \
    -DKDE_INSTALL_USE_QT_SYS_PATHS=ON
  cmake --build build
}

package() {
  cd kwin-fusion
  DESTDIR="$pkgdir" cmake --install build
}
