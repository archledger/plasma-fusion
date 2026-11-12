# Maintainer: Wisbendji Fimerlus <archledger236 at gmail dot com>
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The Plasma Fusion fork of KWin for Arch Linux (the full profile's pinned compositor, ADR 0001
# in archledger/plasma-fusion). Built from the fork's signed release tag. The full profile
# installs this alongside the plasma-fusion packages; the stock profile never touches it.
#
# The pf sequence is part of pkgver (6.8.2.pf3, not 6.8.2): a new tag of the same upstream
# version must compare newer, or pacman would keep the old fork and the full profile's pin could
# not tell the releases apart. Bump _pfnum with each fork tag; _upstream with each rebase.
_upstream=6.8.2
_pfnum=3
pkgname=kwin-fusion
pkgver=${_upstream}.pf${_pfnum}
pkgrel=1
pkgdesc="KDE Window Manager — the Plasma Fusion fork (the full profile's pinned compositor)"
arch=(x86_64)
url="https://github.com/archledger/kwin"
license=('BSD-2-Clause' 'BSD-3-Clause' 'CC0-1.0' 'GPL-2.0-only' 'GPL-2.0-or-later' 'GPL-3.0-only' 'GPL-3.0-or-later' 'LGPL-2.0-only' 'LGPL-2.0-or-later' 'LGPL-2.1-only' 'LGPL-2.1-or-later' 'LGPL-3.0-only' 'MIT')
depends=(gcc-libs glibc kconfig kcoreaddons kcrash kglobalaccel ki18n kio knotifications
         kpackage kservice kwidgetsaddons kwindowsystem libdisplay-info libdrm libepoxy
         libplasma libxcb libxkbcommon libxcvt qt6-5compat qt6-base qt6-declarative qt6-svg
         qt6-wayland systemd-libs wayland)
makedepends=(git cmake ninja extra-cmake-modules python
             qt6-base qt6-declarative qt6-tools qt6-wayland qt6-svg qt6-5compat
             qt6-shadertools qt6-virtualkeyboard libqaccessibilityclient-qt6
             kcompletion kconfig kconfigwidgets kcoreaddons kcrash kdeclarative
             kglobalaccel ki18n kidletime kio knewstuff knotifications kpackage
             kservice ktextwidgets kwidgetsaddons kwindowsystem kxmlgui solid sonnet
             libplasma kdecoration plasma-workspace libkscreen plasma-activities
             breeze
             libx11 libxi libxkbcommon-x11 xcb-util xcb-util-cursor xcb-util-keysyms
             libdisplay-info mesa libcap lcms2 glib2 pipewire wayland-protocols
             libinput libevdev systemd)
provides=("kwin=${pkgver}")
conflicts=('kwin')
source=("kwin-fusion::git+https://github.com/archledger/kwin.git#tag=v${_upstream}-pf${_pfnum}?signed")
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
