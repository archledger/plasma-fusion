# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# NixOS module for Plasma Fusion (docs/parts/nixos.md).
#
#   imports = [ "${plasma-fusion-src}/packaging/nix/module.nix" ];
#   programs.plasma-fusion = { enable = true; src = plasma-fusion-src; };
#
# It installs the shared part and, on Plasma 6.7 or later, the three compiled parts, all built from
# the system's own kdePackages, so every nixos-rebuild builds them against the KWin it ships (a
# failed build stops the rebuild before anything changes). Each user then runs the per-user step
# inside the Plasma session: /run/current-system/sw/share/plasma-fusion/tools/device/fusion-config.sh
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.plasma-fusion;
  pf = import ./plasma-fusion.nix { inherit pkgs; inherit (cfg) src; };
  plasma67 = lib.versionAtLeast pkgs.kdePackages.kwin.version "6.7";
in
{
  options.programs.plasma-fusion = {
    enable = lib.mkEnableOption "Plasma Fusion (themes, widgets, icons, fonts and setup tools)";
    src = lib.mkOption {
      type = lib.types.path;
      description = "Plasma Fusion source tree: a pinned fetchGit or fetchFromGitHub, or a local checkout.";
    };
    compiledParts = lib.mkOption {
      type = lib.types.bool;
      default = plasma67;
      defaultText = lib.literalExpression ''lib.versionAtLeast pkgs.kdePackages.kwin.version "6.7"'';
      description = "Window decoration, settings module and tablet navigation effect (need Plasma 6.7 or later).";
    };
    plymouth = lib.mkEnableOption "the Plasma Fusion boot splash (replaces tools/system/plymouth-install.sh)";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = config.services.desktopManager.plasma6.enable;
          message = "programs.plasma-fusion needs services.desktopManager.plasma6.enable";
        }
        {
          assertion = plasma67;
          message = "Plasma Fusion needs Plasma 6.7 or later; this nixpkgs has ${pkgs.kdePackages.kwin.version} (use nixos-unstable until a NixOS release has 6.7)";
        }
      ];
      # share/ and libexec/ are linked into /run/current-system/sw (the plasma6 module links them);
      # the Qt plugin and QML directories are on the session's plugin and import paths.
      environment.systemPackages = [ pf.plasma-fusion ]
        ++ lib.optionals cfg.compiledParts [ pf.plasma-fusion-decoration pf.plasma-fusion-settings pf.plasma-fusion-navigation ];
      environment.pathsToLink = [ "/libexec/plasma-fusion" ];
      # Manrope and Space Grotesk for every user (fontconfig reads fonts.packages).
      fonts.packages = [ pf.plasma-fusion ];
    }
    (lib.mkIf cfg.plymouth {
      boot.plymouth = {
        enable = true;
        theme = "plasma-fusion";
        themePackages = [ pf.plasma-fusion ];
      };
    })
  ]);
}
