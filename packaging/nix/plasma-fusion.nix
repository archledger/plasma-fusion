# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasma Fusion for NixOS: the shared part (what tools/build.sh stages: themes, widgets, icons,
# fonts, the setup and login-check tools) and the three compiled parts, built from the system's own
# kdePackages. Used by ./module.nix; Plasma 6.7 or later (nixos-unstable while NixOS 26.05 has 6.6).
#   pkgs:    a nixpkgs package set
#   src:     a Plasma Fusion source tree (a pinned fetchGit or fetchFromGitHub, or a checkout)
#   version: the packages' version (default: the tree's VERSION)
{ pkgs, src, version ? pkgs.lib.trim (builtins.readFile "${src}/VERSION") }:
let
  inherit (pkgs) lib stdenv stdenvNoCC kdePackages;
  python = pkgs.python3.withPackages (ps: [ ps.pillow ps.numpy ps.pyside6 ]);
  # NixOS links environment.systemPackages here; /usr/share and /usr/libexec do not exist.
  sw = "/run/current-system/sw";
  compiled = { pname, version, dir, buildInputs, cmakeFlags ? [ ] }:
    stdenv.mkDerivation {
      inherit pname version buildInputs cmakeFlags;
      src = "${src}/packages/${dir}";
      # The settings module compiles in packages/common/FusionMetrics.qml (found as common/).
      postUnpack = ''
        cp -r ${src}/packages/common "$sourceRoot/common"
        chmod -R u+w "$sourceRoot/common"
      '';
      nativeBuildInputs = [ pkgs.cmake pkgs.ninja pkgs.pkg-config kdePackages.extra-cmake-modules ];
      # Plugins loaded by KWin and System Settings: nothing to wrap.
      dontWrapQtApps = true;
    };
in
rec {
  plasma-fusion = stdenvNoCC.mkDerivation {
    pname = "plasma-fusion";
    inherit version src;
    nativeBuildInputs = [ python pkgs.librsvg kdePackages.qtshadertools pkgs.libxml2 pkgs.desktop-file-utils pkgs.makeWrapper ];
    dontConfigure = true;
    # qtshadertools (qsb) brings Qt's setup hook; nothing here is a Qt application to wrap.
    dontWrapQtApps = true;
    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR QT_QPA_PLATFORM=offscreen
      export QT_PLUGIN_PATH=${kdePackages.qtbase}/${kdePackages.qtbase.qtPluginPrefix}:${kdePackages.qtsvg}/${kdePackages.qtbase.qtPluginPrefix}
      export FONTCONFIG_FILE=${pkgs.makeFontsConf { fontDirectories = [ ]; }}
      patchShebangs tools generators packages
      STAGE=$PWD/_stage bash tools/build.sh
      bash generators/plymouth/build.sh "$PWD/_plymouth/plasma-fusion"
      runHook postBuild
    '';
    # packaging/install-tree.sh, as every channel: the files that name another package's data point
    # into the system profile (${sw}/share: the icon names handed back to Breeze and hicolor, the
    # polkit action the charge limit checks, the on-screen keyboard's desktop file), those that name
    # this package's helpers (polkit's exec.path, the quick settings tile) into $out, and the boot
    # splash is a theme for boot.plymouth.themePackages with its own store path.
    installPhase = ''
      runHook preInstall
      bash packaging/install-tree.sh --stage _stage --plymouth _plymouth/plasma-fusion \
        --prefix $out --libexecdir $out/libexec --system-share ${sw}/share --plymouth-theme
      runHook postInstall
    '';
    # fixupPhase patches the shebangs of $out (bash and python3 from the store). The helpers then get
    # the programs they run in their PATH: on Fedora those are all in /usr/bin, on NixOS gdbus and
    # rsvg-convert are in no profile by default, and pkexec starts the charge-limit helper with a
    # PATH of /usr/bin and /bin only. The system profile stays last, for programs a user installs
    # (tlp).
    postFixup = ''
      wrapProgram $out/libexec/plasma-fusion/plasma-fusion-powerfx \
        --prefix PATH : ${lib.makeBinPath [ pkgs.glib.bin pkgs.systemd kdePackages.kconfig pkgs.coreutils pkgs.util-linux pkgs.gnused ]} \
        --suffix PATH : ${sw}/bin
      wrapProgram $out/libexec/plasma-fusion/plasma-fusion-app-icons \
        --prefix PATH : ${lib.makeBinPath [ pkgs.librsvg pkgs.systemd ]} \
        --suffix PATH : ${sw}/bin
      wrapProgram $out/libexec/plasma-fusion/plasma-fusion-charge-limit \
        --prefix PATH : ${lib.makeBinPath [ pkgs.coreutils pkgs.gnugrep pkgs.systemd ]} \
        --suffix PATH : ${sw}/bin
    '';
    meta = {
      description = "Plasma Fusion: a KDE Plasma 6 desktop (themes, widgets, icons, fonts and setup tools)";
      homepage = "https://github.com/archledger/plasma-fusion";
      license = with lib.licenses; [ gpl2Plus cc-by-sa-40 cc0 ofl ];
      platforms = lib.platforms.linux;
    };
  };

  plasma-fusion-decoration = compiled {
    pname = "plasma-fusion-decoration"; inherit version; dir = "decoration-cpp";
    buildInputs = with kdePackages; [ qtbase kdecoration kcoreaddons kconfig kcolorscheme ];
    cmakeFlags = [ "-DBUILD_TESTING=OFF" ];
  };

  plasma-fusion-settings = compiled {
    pname = "plasma-fusion-settings"; inherit version; dir = "kcm-cpp";
    buildInputs = with kdePackages; [ qtbase qtdeclarative kconfig kcoreaddons ki18n kcmutils ];
    cmakeFlags = [ "-DBUILD_TESTING=OFF" ];
  };

  plasma-fusion-navigation = compiled {
    pname = "plasma-fusion-navigation"; inherit version; dir = "navigation-cpp";
    buildInputs = (with kdePackages; [ qtbase qtdeclarative kwin kconfigwidgets kglobalaccel ki18n kcoreaddons
      kwindowsystem kpackage plasma-activities ]) ++ [ pkgs.libepoxy pkgs.libdrm pkgs.vulkan-headers ];
  };
}
