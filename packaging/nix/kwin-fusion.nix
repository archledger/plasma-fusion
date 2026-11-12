# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The Plasma Fusion fork of KWin for NixOS (the full profile's pinned compositor, ADR 0001).
# Used by ./module.nix's full-profile option; the stock module never pulls this in.
#
#   pkgs:      a nixpkgs package set
#   src:       the fork's source tree (a pinned fetchFromGitHub)
#   version:   the fork's version (e.g. "6.8.2-pf3")
{ pkgs, src, version }:

let
  inherit (pkgs) lib stdenv;
  inherit (pkgs.kdePackages)
    qtbase qtdeclarative qtwayland qtsvg qt5compat qtmultimedia
    extra-cmake-modules
    kcompletion kconfig kconfigwidgets kcoreaddons kcrash kdeclarative
    kglobalaccel ki18n kidletime kio knewstuff knotifications kpackage
    kservice ktextwidgets kwidgetsaddons kwindowsystem kxmlgui solid sonnet
    libplasma kdecoration plasma-workspace libkscreen
    kactivities;
in
stdenv.mkDerivation {
  pname = "kwin-fusion";
  inherit version src;

  # KWin's build is large; the fork adds the transient tiling system but does not
  # add new external dependencies beyond stock KWin's.
  nativeBuildInputs = [
    extra-cmake-modules
    pkgs.cmake
    pkgs.ninja
    pkgs.pkg-config
    qtbase
    qtdeclarative
  ];

  buildInputs = [
    qtbase
    qtdeclarative
    qtwayland
    qtsvg
    qt5compat
    kcompletion
    kconfig
    kconfigwidgets
    kcoreaddons
    kcrash
    kdeclarative
    kglobalaccel
    ki18n
    kidletime
    kio
    knewstuff
    knotifications
    kpackage
    kservice
    ktextwidgets
    kwidgetsaddons
    kwindowsystem
    kxmlgui
    solid
    sonnet
    libplasma
    kdecoration
    plasma-workspace
    libkscreen
    kactivities
    pkgs.libxcvt
    pkgs.libxkbcommon
    pkgs.libXi
    pkgs.libX11
    pkgs.libxcb-cursor
    pkgs.libepoxy
    pkgs.mesa
    pkgs.libGL
    pkgs.libcap
    pkgs.lcms2
    pkgs.glib
    pkgs.pipewire
    pkgs.wayland
    pkgs.wayland-protocols
    pkgs.libinput
    pkgs.libevdev
    pkgs.libudev
    pkgs.systemd
  ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DBUILD_TESTING=OFF"
    "-DKDE_INSTALL_USE_QT_SYS_PATHS=ON"
  ];

  # The fork's QML facade (TransientTilingApi) registers in the org.kde.kwin module;
  # the QML import path must be present.
  postInstall = ''
    mkdir -p $out/${pkgs.qtbase.qtQmlPrefix}
  '';

  meta = with lib; {
    description = "KDE Window Manager — the Plasma Fusion fork (the full profile's compositor)";
    homepage = "https://github.com/archledger/kwin";
    license = with licenses; [ bsd2 bsd3 cc0 gpl2Plus gpl2Only gpl3Plus gpl3Only lgpl2Plus lgpl2Only lgpl21Plus lgpl21Only lgpl3Plus mit ];
    maintainers = [ maintainers.archledger ];
    platforms = platforms.linux;
  };
}
